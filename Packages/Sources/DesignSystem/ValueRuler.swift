import SwiftUI

/// A value set by dragging a ruler sideways under a fixed line at its center. Ticks hang from
/// its top edge, one per `tick` across `range`: short and gray, a medium one at each 2.5, and a
/// tall, lighter one with its number under it at each 5. It flicks with the system's momentum
/// and always comes to rest on a tick. While a finger moves it, every tick under the line is
/// written through `onChange`; a value changed from outside (a − / + key) slides it there,
/// animated. VoiceOver skips it: the row it sits in steps the same value.
public struct ValueRuler: View {
    private let value: Double
    private let range: ClosedRange<Double>
    private let tick: Double
    private let onChange: (Double) -> Void

    @State private var position = ScrollPosition(x: 0)
    /// While a finger drags the ruler or its flick runs on, when the ruler writes the value
    /// rather than follows it.
    @State private var isScrolling = false
    @State private var width: CGFloat = 0

    /// Wide enough to drag a tick at a time, narrow enough that a flick covers tens of pounds.
    static let spacing: CGFloat = 8
    static let minorHeight: CGFloat = 10
    static let mediumHeight: CGFloat = 16
    static let majorHeight: CGFloat = 24
    static let lineHeight: CGFloat = majorHeight + Spacing.xxs
    static let tickWidth: CGFloat = 1.5
    static let lineWidth: CGFloat = 2.5

    public init(
        value: Double,
        range: ClosedRange<Double>,
        tick: Double = 0.5,
        onChange: @escaping (Double) -> Void,
    ) {
        self.value = value
        self.range = range
        self.tick = tick
        self.onChange = onChange
    }

    private var count: Int {
        Int(((range.upperBound - range.lowerBound) / tick).rounded()) + 1
    }

    private func index(of value: Double) -> Int {
        let index = Int(((value - range.lowerBound) / tick).rounded())
        return min(max(index, 0), count - 1)
    }

    /// The scroll offset that puts a value's tick under the line: the content leads with half the
    /// ruler's width less half a cell, so offset 0 centers the first tick.
    private func offset(of value: Double) -> CGFloat {
        CGFloat(index(of: value)) * Self.spacing
    }

    public var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    tickCell(range.lowerBound + Double(index) * tick)
                }
            }
            .padding(.horizontal, max(0, width / 2 - Self.spacing / 2))
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollTargetBehavior(TickSnap(spacing: Self.spacing))
        .onScrollPhaseChange { _, phase in
            switch phase {
            case .tracking, .interacting, .decelerating: isScrolling = true
            case .idle, .animating: isScrolling = false
            @unknown default: isScrolling = false
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
            guard isScrolling else { return }
            let index = min(max(Int((x / Self.spacing).rounded()), 0), count - 1)
            let new = range.lowerBound + Double(index) * tick
            if new != value {
                onChange(new)
            }
        }
        .onChange(of: value) { _, value in
            guard !isScrolling else { return }
            withAnimation(.snappy(duration: 0.25)) {
                position.scrollTo(x: offset(of: value))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            self.width = width
            position.scrollTo(x: offset(of: value))
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(.pp(.textPrimary))
                .frame(width: Self.lineWidth, height: Self.lineHeight)
                .allowsHitTesting(false)
        }
        // The ticks fade over the last few points to the row's edges, so a number scrolling off
        // goes soft rather than cut.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
            }
        }
        .accessibilityHidden(true)
    }

    static let edgeFade: CGFloat = Spacing.lg

    private func tickCell(_ mark: Double) -> some View {
        let isMajor = mark.isMultiple(of: 5)
        let isMedium = mark.isMultiple(of: 2.5)
        let height = isMajor ? Self.majorHeight : isMedium ? Self.mediumHeight : Self.minorHeight
        return VStack(spacing: Spacing.xs) {
            Rectangle()
                .fill(.pp(isMajor ? .textSecondary : .borderStrong))
                .frame(width: Self.tickWidth, height: height)
                .frame(height: Self.majorHeight, alignment: .top)
            // A line's room under every tick, so each cell is as tall; the number, wider than a
            // cell, overflows it centered on its tick.
            Text(verbatim: "0")
                .font(.ppRowDetailNumber)
                .hidden()
                .overlay {
                    if isMajor {
                        Text(mark.formatted(.number.precision(.fractionLength(0 ... 1))))
                            .font(.ppRowDetailNumber)
                            .foregroundStyle(.pp(.textSecondary))
                            .fixedSize()
                    }
                }
        }
        .frame(width: Self.spacing)
    }
}

extension Double {
    fileprivate func isMultiple(of step: Double) -> Bool {
        (self / step).rounded() * step == self
    }
}

/// Rests a flick or a drag on the tick nearest where the system would have stopped it, so the
/// deceleration stays the platform's and only its end moves.
private struct TickSnap: ScrollTargetBehavior {
    let spacing: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let maxX = max(0, context.contentSize.width - context.containerSize.width)
        let snapped = (target.rect.origin.x / spacing).rounded() * spacing
        target.rect.origin.x = min(max(snapped, 0), maxX)
    }
}

#Preview {
    @Previewable @State var value = 27.5
    VStack(spacing: Spacing.md) {
        Text(value.formatted())
            .font(.ppRowTitleNumber)
        ValueRuler(value: value, range: 5 ... 1000) { value = $0 }
            .background(Color.pp(.surface))
    }
    .padding()
    .background(Color.pp(.background))
}
