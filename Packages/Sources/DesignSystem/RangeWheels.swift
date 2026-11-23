#if os(iOS)
import SwiftUI
import UIKit

/// Two wheels of bare minutes under one highlight, read as one phrase centered in the band:
/// "20 – 40 min", a dash between the wheels and "min" once, after the right wheel's value. The
/// right wheel's nil value is "∞", no upper limit.
///
/// One `UIPickerView` with two components, as the system's timer picker: it draws one band
/// across both, where two SwiftUI wheel pickers side by side each draw their own. Each
/// component carries its share of the dash's room, and the right one the room for "min", so
/// the components centered by the picker center the whole phrase; the dash and "min" are
/// labels laid over the band, placed from where the picker put the selected rows.
///
/// A turn reports its value at once (`onLower`, `onUpper`); the wheels show whatever values
/// they are handed, turning to them, which is how one wheel follows when the other pushes the
/// range along. VoiceOver reads the wheels as "Shortest" and "Longest", each value in minutes.
public struct RangeWheels: UIViewRepresentable {
    let lower: Int
    let upper: Int?
    let lowerValues: [Int]
    let upperValues: [Int?]
    let onLower: (Int) -> Void
    let onUpper: (Int?) -> Void

    public init(
        lower: Int,
        upper: Int?,
        lowerValues: [Int],
        upperValues: [Int?],
        onLower: @escaping (Int) -> Void,
        onUpper: @escaping (Int?) -> Void,
    ) {
        self.lower = lower
        self.upper = upper
        self.lowerValues = lowerValues
        self.upperValues = upperValues
        self.onLower = onLower
        self.onUpper = onUpper
    }

    public func makeUIView(context: Context) -> RangeWheelsView {
        let view = RangeWheelsView()
        update(view, context: context, animated: false)
        return view
    }

    public func updateUIView(_ view: RangeWheelsView, context: Context) {
        update(view, context: context, animated: true)
    }

    private func update(_ view: RangeWheelsView, context: Context, animated: Bool) {
        view.onLower = onLower
        view.onUpper = onUpper
        let category = UIContentSizeCategory(context.environment.dynamicTypeSize)
        let primary = UIColor(cgColor: Color.pp(.textPrimary).resolve(in: context.environment)
            .cgColor)
        view.configure(
            lowerValues: lowerValues,
            upperValues: upperValues,
            category: category,
            color: primary,
        )
        view.select(
            lowerValues.firstIndex(of: lower) ?? 0,
            upperValues.firstIndex(of: upper) ?? upperValues.count - 1,
            animated: animated,
        )
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: RangeWheelsView,
        context _: Context,
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: uiView.height)
    }
}

/// `RangeWheels`' view: the picker and the two labels over its band.
public final class RangeWheelsView: UIView, UIPickerViewDataSource, UIPickerViewDelegate,
    UIPickerViewAccessibilityDelegate
{
    var onLower: (Int) -> Void = { _ in }
    var onUpper: (Int?) -> Void = { _ in }

    private let picker = UIPickerView()
    private let dash = UILabel()
    private let unit = UILabel()
    private var lowerValues: [Int] = []
    private var upperValues: [Int?] = []
    private var numberFont = UIFont.monospacedSystemFont(ofSize: Wheel.numberSize, weight: .regular)
    private var color = UIColor.label
    private var category: UIContentSizeCategory?

    /// The width a number takes, the widest of the values.
    private var numberWidth: CGFloat = 0
    /// The room the dash takes between the numbers, its gaps included.
    private var dashRoom: CGFloat = 0
    /// The room "min" takes after the right number, its gap included.
    private var unitRoom: CGFloat = 0

    /// How tall the wheels stand: five rows.
    var height: CGFloat {
        rowHeight * 5
    }

    private var rowHeight: CGFloat {
        ceil(numberFont.lineHeight + Wheel.rowPadding)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        picker.dataSource = self
        picker.delegate = self
        addSubview(picker)
        for label in [dash, unit] {
            label.isAccessibilityElement = false
            addSubview(label)
        }
        dash.text = "–"
        unit.text = "min"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(
        lowerValues: [Int],
        upperValues: [Int?],
        category: UIContentSizeCategory,
        color: UIColor,
    ) {
        let changed = lowerValues != self.lowerValues || upperValues != self.upperValues
            || category != self.category || color != self.color
        guard changed else { return }
        self.lowerValues = lowerValues
        self.upperValues = upperValues
        self.category = category
        self.color = color
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        numberFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .monospacedSystemFont(ofSize: Wheel.numberSize, weight: .regular),
            compatibleWith: traits,
        )
        let unitFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        dash.font = numberFont
        dash.textColor = color
        unit.font = unitFont
        unit.textColor = color
        let texts = lowerValues.map(Self.text) + upperValues.map(Self.text)
        numberWidth = ceil(texts.map { width(of: $0, in: numberFont) }.max() ?? 0)
        let gap = UIFontMetrics(forTextStyle: .title2).scaledValue(
            for: Wheel.gap,
            compatibleWith: traits,
        )
        dashRoom = ceil(width(of: "–", in: numberFont) + gap * 2)
        unitRoom = ceil(width(of: "min", in: unitFont) + gap)
        picker.reloadAllComponents()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func select(_ lowerRow: Int, _ upperRow: Int, animated: Bool) {
        if picker.selectedRow(inComponent: 0) != lowerRow {
            picker.selectRow(lowerRow, inComponent: 0, animated: animated)
        }
        if picker.selectedRow(inComponent: 1) != upperRow {
            picker.selectRow(upperRow, inComponent: 1, animated: animated)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        picker.layoutIfNeeded()
        // Where the picker put each wheel's selected number: from its rows once drawn, else
        // the components centered as the picker centers them.
        let leftStart: CGFloat
        let rightStart: CGFloat
        if let left = picker.view(forRow: picker.selectedRow(inComponent: 0), forComponent: 0),
           let right = picker.view(forRow: picker.selectedRow(inComponent: 1), forComponent: 1)
        {
            leftStart = left.convert(left.bounds, to: self).minX
            rightStart = right.convert(right.bounds, to: self).minX
        } else {
            let widths = componentWidth(0) + componentWidth(1)
            leftStart = (bounds.width - widths) / 2
            rightStart = leftStart + componentWidth(0)
        }
        let leftEnd = leftStart + numberWidth
        let rightNumberStart = rightStart + dashRoom / 2
        dash.sizeToFit()
        unit.sizeToFit()
        dash.center = CGPoint(x: (leftEnd + rightNumberStart) / 2, y: bounds.midY)
        // "min" on the numbers' baseline, so it reads as one line with them.
        let baseline = bounds.midY + (numberFont.ascender + numberFont.descender) / 2
        let unitFont = unit.font ?? numberFont
        unit.frame.origin = CGPoint(
            x: rightNumberStart + numberWidth + (unitRoom - unit.bounds.width),
            y: baseline - unitFont.ascender,
        )
    }

    private func componentWidth(_ component: Int) -> CGFloat {
        component == 0 ? numberWidth + dashRoom / 2 : dashRoom / 2 + numberWidth + unitRoom
    }

    private func width(of text: String, in font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func text(_ minutes: Int?) -> String {
        minutes.map(String.init) ?? "∞"
    }

    // MARK: Picker

    public func numberOfComponents(in _: UIPickerView) -> Int {
        2
    }

    public func pickerView(_: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? lowerValues.count : upperValues.count
    }

    public func pickerView(_: UIPickerView, widthForComponent component: Int) -> CGFloat {
        componentWidth(component)
    }

    public func pickerView(_: UIPickerView, rowHeightForComponent _: Int) -> CGFloat {
        rowHeight
    }

    public func pickerView(
        _: UIPickerView,
        viewForRow row: Int,
        forComponent component: Int,
        reusing view: UIView?,
    ) -> UIView {
        let cell = (view as? WheelRow) ?? WheelRow()
        let minutes = component == 0 ? lowerValues[row] : upperValues[row]
        cell.label.text = Self.text(minutes)
        cell.label.font = numberFont
        cell.label.textColor = color
        cell.numberStart = component == 0 ? 0 : dashRoom / 2
        cell.numberWidth = numberWidth
        cell.accessibilityLabel = minutes.map { "\($0) minutes" } ?? "No limit"
        return cell
    }

    public func pickerView(_: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            onLower(lowerValues[row])
        } else {
            onUpper(upperValues[row])
        }
        setNeedsLayout()
    }

    public func pickerView(
        _: UIPickerView,
        accessibilityLabelForComponent component: Int,
    ) -> String? {
        component == 0 ? "Shortest" : "Longest"
    }
}

/// A wheel's row: its number centered in the number's width, at `numberStart` in the row.
private final class WheelRow: UIView {
    let label = UILabel()
    var numberStart: CGFloat = 0
    var numberWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.isAccessibilityElement = false
        addSubview(label)
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: numberStart, y: 0, width: numberWidth, height: bounds.height)
    }
}

/// The wheels' measures at the default text size, scaled as `title2`.
private enum Wheel {
    /// The numbers' and the dash's size.
    static let numberSize: CGFloat = 22
    /// The room above and below a number in its row.
    static let rowPadding: CGFloat = 14
    /// The gap either side of the dash, and before "min".
    static let gap: CGFloat = 14
}

#Preview {
    @Previewable @State var lower = 20
    @Previewable @State var upper: Int? = 40
    RangeWheels(
        lower: lower,
        upper: upper,
        lowerValues: Array(stride(from: 0, through: 90, by: 5)),
        upperValues: Array(stride(from: 0, through: 90, by: 5)) + [nil],
        onLower: { lower = $0
            upper = upper.map { max($0, lower) }
        },
        onUpper: { upper = $0
            lower = $0.map { min(lower, $0) } ?? lower
        },
    )
    .padding()
    .background(Color.pp(.surface))
}
#endif
