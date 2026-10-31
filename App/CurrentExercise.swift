import DesignSystem
import SwiftUI
import WorkoutStore

/// Where the current exercise's row is against the part of the list showing. Coarse where it
/// changes as the list scrolls, so a scroll changes it only as the row crosses a threshold.
nonisolated struct CurrentPlace: Equatable {
    /// Whether the row was placed in a list with a height, not in the first pass, before the
    /// scroll view has its size, which lays the row out at no width, its place far off.
    var isLaidOut: Bool
    /// Scrolled fully or mostly out of view, under 40 percent of as much as could show, where
    /// the way back to it shows.
    var isMostlyOut: Bool
    /// Whether the row is above the part showing, so the way back to it is up.
    var isAbove: Bool
    /// How far the label's top, with the current exercise's space above it, is from the top of
    /// the list's content, where `scrollTo(y:)` counts from.
    var contentTop: CGFloat

    /// The scroll position that lands the rail row, its label `RailRowMetrics.verticalInset`
    /// below its top, just under the bar.
    @MainActor var landingY: CGFloat {
        max(contentTop - RailRowMetrics.verticalInset, 0)
    }

    init(_ proxy: GeometryProxy) {
        let row = CGRect(origin: .zero, size: proxy.size)
        contentTop = proxy.frame(in: .list).minY
        guard let visible = proxy.bounds(of: .scrollView) else {
            (isLaidOut, isMostlyOut, isAbove) = (true, false, false)
            return
        }
        let overlap = row.intersection(visible)
        let most = min(row.height, visible.height)
        let shown = overlap.isNull || most <= 0 ? 0 : overlap.height / most
        isLaidOut = visible.height > 0
        isMostlyOut = shown < 0.4
        isAbove = row.midY < visible.midY
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The routine screen's list content, from its top, as a scroll position counts.
    nonisolated static var list: NamedCoordinateSpace {
        .named("RoutineScreen.list")
    }
}

extension View {
    /// A row's Delete, revealed by a swipe, while `isOn`. Off, on the current exercise, which
    /// fills the screen and whose sheet deletes it, there is no swipe at all: with no actions the
    /// row still slid aside.
    func swipeToDelete(isOn: Bool, delete: @escaping () -> Void) -> some View {
        // The row itself stays on, or VoiceOver would read it dimmed.
        environment(\.isEnabled, true)
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive, action: delete)
            }
            .disabled(!isOn)
    }

    /// While `isOn`, room under this view as tall as the scroll view it is in shows, out of sight,
    /// so the list can scroll its end up to the top. Sized in the same layout pass as the list,
    /// so a change to what shows, as a workout's margin coming or going, changes it at once: as
    /// a height read back from the scroll view, it changed the list a second time in the frame.
    func roomBelow(_ isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self
            if isOn {
                Color.clear.containerRelativeFrame(.vertical)
            }
        }
    }

    /// In a workout, room under this view, out of sight, so the list can scroll the current
    /// exercise's row, its top at `top` in the list, up under the bar even where what follows it
    /// is shorter than the height the scroll view shows above its content margin. Worked out in
    /// the pass that lays the list out, from its own height and the scroll view's, so it is right
    /// on every frame of a growth: the scroll view's height read back into state, as `roomBelow`
    /// found, changed the list a second time in a frame. None out of a workout.
    func roomToLand(top: CGFloat?) -> some View {
        RoomToLand(top: top ?? 0, isOn: top != nil) {
            self
            // What the scroll view shows above its content margin, measured in the same pass.
            Color.clear.containerRelativeFrame(.vertical)
        }
    }

    /// Reports this row's frame in the list's content as it lays out, while `isOn`.
    func reportingFrame(_ isOn: Bool, to action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect?.self) { proxy in
            isOn ? proxy.frame(in: .list) : nil
        } action: { frame in
            if let frame {
                action(frame)
            }
        }
    }

    /// Reports where this row is in the list as it scrolls, while `isOn`.
    func reportingPlace(_ isOn: Bool, to action: @escaping (CurrentPlace) -> Void) -> some View {
        onGeometryChange(for: CurrentPlace?.self) { proxy in
            isOn ? CurrentPlace(proxy) : nil
        } action: { place in
            if let place {
                action(place)
            }
        }
    }
}

extension RoutineExercise {
    /// The row grown into the current exercise, on `set`.
    func focus(on set: PlannedSet, inSuperset: Bool, locale: Locale) -> RowFocus {
        RowFocus(
            progress: progressText(set: set.round, inSuperset: inSuperset, locale: locale),
            side: set.side?.text,
            equipment: [exercise].equipment.map(\.name),
            figures: figures(side: set.side, locale: locale)
                .map { .init(number: $0.number, unit: $0.unit) },
            spokenFigures: spokenFigures(side: set.side, locale: locale),
        )
    }
}

/// Everything but the top `height` of a view, which nothing else is cut from: the list going out
/// in a crossfade up to its top, lifted to hold still, would show what was under the bar above
/// it, where the bar has no edge effect at the top of a list. A rectangle, so the cut is cheap.
nonisolated struct TopClip: Shape {
    var height: CGFloat

    func path(in rect: CGRect) -> Path {
        let far = max(rect.width, rect.height) * 4
        let top = height > 0 ? rect.minY + height : rect.minY - far
        return Path(CGRect(
            x: rect.minX - far,
            y: top,
            width: rect.width + far * 2,
            height: rect.maxY + far - top,
        ))
    }
}

/// At Start, the list's content drawn `lift` below where it is scrolled to. Animatable, so the lift
/// is worked out frame by frame with the current exercise's growth, and the rows below it move
/// exactly as far as Start riding down with them: as an offset, it ran ahead of the growth.
struct GrowthLift: ViewModifier, Animatable {
    var lift: CGFloat

    nonisolated var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(y: lift)
    }
}

/// Its first subview, with room under it while `isOn`: as much as `top` plus what the scroll view
/// shows, its second subview's height, reaches past its height. `top` animates, so the room can
/// close over a motion.
private struct RoomToLand: Layout {
    var top: CGFloat
    let isOn: Bool

    var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        guard isOn, subviews.count > 1 else { return size }
        let visible = subviews[1].sizeThatFits(proposal).height
        return CGSize(width: size.width, height: max(size.height, top + visible))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
        // Measured only: placed at the top with no size of its own in the room.
        subviews.dropFirst().first?.place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
    }
}
