import DesignSystem
import SwiftUI
import WorkoutStore

/// Where the current exercise's row is against the part of the list showing. Coarse where it
/// changes as the list scrolls, so a scroll changes it only as the row crosses a threshold.
nonisolated struct CurrentPlace: Equatable {
    /// Whether the row was placed in a list with a height, not in the first pass, before the
    /// scroll view has its size, which lays the row out at no width, its place far off.
    var isLaidOut: Bool
    /// A third or more of it out of view, between the bars, where the way back to it shows: at
    /// 60 percent out, the key stood over the current exercise's numbers and still read "Log
    /// set".
    var isScrolledAway: Bool
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
        // The part between the bars: the scroll view's bounds leave out what is under them.
        guard let visible = proxy.bounds(of: .scrollView) else {
            (isLaidOut, isScrolledAway, isAbove) = (true, false, false)
            return
        }
        let overlap = row.intersection(visible)
        let most = min(row.height, visible.height)
        let shown = overlap.isNull || most <= 0 ? 0 : overlap.height / most
        isLaidOut = visible.height > 0
        isScrolledAway = shown < 2 / 3
        isAbove = row.midY < visible.midY
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The workout screen's list content, from its top, as a scroll position counts.
    nonisolated static var list: NamedCoordinateSpace {
        .named("WorkoutScreen.list")
    }
}

extension View {
    /// Row `id`'s Remove, revealed by a swipe, while `isOn`. Off, on the current exercise, which
    /// fills the screen and whose sheet deletes it, there is no swipe at all: with no actions the
    /// row still slid aside. `delete` is kept from the last build for the same `id`
    /// (`rowSwipe(_:value:action:)`).
    func swipeToDelete(
        _ id: WorkoutExercise.ID,
        isOn: Bool,
        delete: @escaping (WorkoutExercise.ID) -> Void,
    ) -> some View {
        // The row itself stays on, or VoiceOver would read it dimmed.
        environment(\.isEnabled, true)
            .rowSwipe("Remove", value: id, action: delete)
            .disabled(!isOn)
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

extension WorkoutExercise {
    /// The row grown into the current exercise, on `set`.
    func focus(on set: PlannedSet, inSuperset: Bool, locale: Locale) -> RowFocus {
        RowFocus(
            place: place(set: set.round, inSuperset: inSuperset, locale: locale),
            side: set.side?.text,
            equipment: [exercise].equipment.map(\.name),
            figures: shownFigures(side: set.side, locale: locale)
                .map { .init(number: $0.number, unit: $0.unit) },
            spokenFigures: spokenFigures(side: set.side, locale: locale),
        )
    }

    /// Which set or round of its plan `set` is, "Set 1 of 3", as its caption line shows it.
    func place(set: Int, inSuperset: Bool, locale: Locale) -> SetPlace {
        SetPlace(
            word: Self.progressWord(inSuperset: inSuperset),
            number: set,
            total: plan.sets,
            locale: locale,
        )
    }

    /// The figures as the current exercise shows them, each number over what it counts: a time
    /// under a minute as its seconds over "seconds", "30" "seconds"; a minute or more as a clock
    /// over "min", "1:30" "min", which a plural unit misread as "1:00 minutes"; with "per side"
    /// after it where the plan's figure has it, so it reads as reps and weight do.
    func shownFigures(side: Side?, locale: Locale) -> [(number: String, unit: String)] {
        figures(side: side, locale: locale).enumerated().map { index, figure in
            guard index == 0, case let .time(seconds) = plan.target else {
                return (figure.number, figure.unit)
            }
            let number = seconds < 60
                ? seconds.formatted(.number.locale(locale))
                : Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))
            let unit = seconds < 60 ? String(localized: "seconds") : String(localized: "min")
            return (number, [unit, figure.unit].filter { !$0.isEmpty }.joined(separator: " "))
        }
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
/// It records the lift it draws in `shown`, so End can take up a lift still running from where it
/// is drawn: the state already holds the lift's end.
struct GrowthLift: ViewModifier, Animatable {
    var lift: CGFloat
    let shown: ShownLift

    nonisolated var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func body(content: Content) -> some View {
        shown.value = lift
        // Read on each frame by a figure carried over the rows (`FigureCarry`).
        return content.offset(y: lift).environment(\.listLift, lift)
    }
}

/// The lift as `GrowthLift` last drew it. Not observed: written as it draws.
final class ShownLift {
    var value: CGFloat = 0
}
