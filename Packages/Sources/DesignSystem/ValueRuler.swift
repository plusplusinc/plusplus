import SwiftUI

/// A value set by dragging a ruler sideways under a fixed line at its center. Ticks hang from
/// its top edge, one per `tick` across `range`, `spacing` apart: short and gray, a medium one at
/// each multiple of `medium`, and a tall, lighter one with its `label` under it at each multiple
/// of `major` (a weight's: 0.5 a tick, 2.5 and 5). `spacing` is at the default text size and
/// scales as the labels' text style does, so at the accessibility sizes the labels keep their
/// room between ticks; every position, the line's, a snap's, a drag's tick, is worked out from
/// that one scaled spacing (`RulerScale`). It flicks with the system's momentum and
/// always comes to rest on a tick. While a finger moves it, every tick under the line is written
/// through `onChange`; a value changed from outside (a − / + key, an Auto switch) slides it
/// there, animated, between two ticks if it falls off them. VoiceOver skips it: the row it sits
/// in steps the same value.
public struct ValueRuler: View {
    private let value: Double
    private let range: ClosedRange<Double>
    private let tick: Double
    private let medium: Double
    private let major: Double
    private let label: (Double) -> String
    private let onChange: (Double) -> Void

    @State private var position = ScrollPosition()
    /// While a finger drags the ruler or its flick runs on, when the ruler writes the value
    /// rather than follows it.
    @State private var isScrolling = false
    /// `spacing`, scaled with the labels' text style.
    @ScaledMetric private var spacing: CGFloat

    /// A weight's: wide enough to drag a tick at a time, narrow enough that a flick covers tens
    /// of pounds.
    public static let weightSpacing: CGFloat = 8
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
        medium: Double = 2.5,
        major: Double = 5,
        spacing: CGFloat = weightSpacing,
        label: @escaping (Double) -> String = {
            $0.formatted(.number.precision(.fractionLength(0 ... 1)))
        },
        onChange: @escaping (Double) -> Void,
    ) {
        self.value = value
        self.range = range
        self.tick = tick
        self.medium = medium
        self.major = major
        _spacing = ScaledMetric(wrappedValue: spacing, relativeTo: Self.labelStyle)
        self.label = label
        self.onChange = onChange
    }

    /// The labels' text style, which `ppRowDetailNumber` is set in and the spacing scales with.
    static let labelStyle = Font.TextStyle.subheadline

    private var scale: RulerScale {
        RulerScale(range: range, tick: tick, spacing: spacing)
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                leadRoom
                LazyHStack(spacing: 0) {
                    ForEach(0 ..< scale.count, id: \.self) { index in
                        tickCell(range.lowerBound + Double(index) * tick)
                    }
                }
                .scrollTargetLayout()
                leadRoom
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        // Where the ruler starts, and where it stays as its width or spacing changes: the value's
        // place along the ticks, as a fraction, which puts it under the line at any width.
        .defaultScrollAnchor(scale.anchor(of: value))
        .scrollTargetBehavior(TickSnap(scale: scale))
        .onScrollPhaseChange { _, phase in
            switch phase {
            case .tracking, .interacting, .decelerating: isScrolling = true
            case .idle, .animating: isScrolling = false
            @unknown default: isScrolling = false
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
            guard isScrolling else { return }
            let new = scale.value(at: x)
            if new != value {
                // The step keys' own animation, so the row's digits roll here as they do there.
                withAnimation(Self.step) {
                    onChange(new)
                }
            }
        }
        .onChange(of: value) { _, value in
            guard !isScrolling else { return }
            withAnimation(Self.slide) {
                position.scrollTo(x: scale.offset(of: value))
            }
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

    /// Room before the first tick and after the last, half the ruler's width less half a tick,
    /// so either end can come under the line. Sized from the scroll view's own width in the
    /// same layout pass as the ticks: from a width kept in state, the first layout had none,
    /// and the scroll view kept the offset's content in place as the room arrived, so the line
    /// sat half a ruler's width of ticks past the value, and stayed there.
    private var leadRoom: some View {
        Color.clear
            .frame(height: 0)
            .containerRelativeFrame(.horizontal) { width, _ in max(0, width / 2 - spacing / 2) }
    }

    /// The step keys' own animation, which a drag writes its ticks in.
    static let step = Animation.snappy(duration: 0.15)
    /// A value changed from outside slides the ruler there.
    static let slide = Animation.snappy(duration: 0.25)

    private func tickCell(_ mark: Double) -> some View {
        let isMajor = mark.isMultiple(of: major)
        let isMedium = mark.isMultiple(of: medium)
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
                        Text(label(mark))
                            .font(.ppRowDetailNumber)
                            .foregroundStyle(.pp(.textSecondary))
                            .fixedSize()
                    }
                }
        }
        .frame(width: spacing)
    }
}

extension Double {
    fileprivate func isMultiple(of step: Double) -> Bool {
        (self / step).rounded() * step == self
    }
}

/// Where a ruler's values sit along its content, `spacing` apart a tick: the scroll offset that
/// puts a value under the center line, and the tick a scroll offset rests on. The content leads
/// with half the ruler's width less half a tick, so offset 0 centers the first tick.
struct RulerScale: Equatable {
    let range: ClosedRange<Double>
    let tick: Double
    let spacing: CGFloat

    var count: Int {
        Int(((range.upperBound - range.lowerBound) / tick).rounded()) + 1
    }

    /// The offset that puts `value`, held to the range, under the line. A value off the ticks
    /// (a typed 27.3 lb) sits between its two, where it falls.
    func offset(of value: Double) -> CGFloat {
        let ticks = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / tick
        return CGFloat(ticks) * spacing
    }

    /// The value of the tick nearest the line at offset `x`, held to the range.
    func value(at x: CGFloat) -> Double {
        let index = min(max(Int((x / spacing).rounded()), 0), count - 1)
        return range.lowerBound + Double(index) * tick
    }

    /// The scroll anchor that puts `value` under the line, whatever the ruler's width or
    /// spacing: content and ruler lead and trail by the same room, so the content's point at a
    /// fraction of its width lines up with the ruler's at that fraction when the offset is that
    /// fraction of the ticks' span.
    func anchor(of value: Double) -> UnitPoint {
        let span = CGFloat(count - 1) * spacing
        return UnitPoint(x: span > 0 ? offset(of: value) / span : 0, y: 0.5)
    }

    /// The offset of the tick nearest `x`, so a scroll comes to rest with a tick under the line.
    func snapped(_ x: CGFloat) -> CGFloat {
        (x / spacing).rounded() * spacing
    }
}

/// Rests a flick or a drag on the tick nearest where the system would have stopped it, so the
/// deceleration stays the platform's and only its end moves.
private struct TickSnap: ScrollTargetBehavior {
    let scale: RulerScale

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let maxX = max(0, context.contentSize.width - context.containerSize.width)
        target.rect.origin.x = min(max(scale.snapped(target.rect.origin.x), 0), maxX)
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
