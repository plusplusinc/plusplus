import DesignSystem
import SwiftUI
import WorkoutStore

/// Where the current exercise's row is against the part of the list showing.
nonisolated struct CurrentPlace: Equatable {
    /// How much of the row shows, of as much as could: 0 out of view, 1 all of it, or all the
    /// list has room for.
    var shown: CGFloat
    /// Whether the row is above the part showing, so the way back to it is up.
    var isAbove: Bool
    /// How far the label's top is below the bar, the top of the part showing.
    var top: CGFloat
    /// How far the label's top is from the top of the list's content, where `scrollTo(y:)`
    /// counts from.
    var contentTop: CGFloat

    /// Scrolled fully or mostly out of view, where the way back to it shows.
    var isMostlyOut: Bool {
        shown < 0.4
    }

    /// How far the rail row's top is below the bar: the label is `RailRowMetrics.verticalInset`
    /// below it.
    @MainActor var rowTop: CGFloat {
        top - RailRowMetrics.verticalInset
    }

    /// The rail row's top in the list's content.
    @MainActor var rowContentTop: CGFloat {
        contentTop - RailRowMetrics.verticalInset
    }

    init(_ proxy: GeometryProxy) {
        let row = CGRect(origin: .zero, size: proxy.size)
        guard let visible = proxy.bounds(of: .scrollView) else {
            (shown, isAbove, top, contentTop) = (1, false, 0, 0)
            return
        }
        let overlap = row.intersection(visible)
        let most = min(row.height, visible.height)
        shown = overlap.isNull || most <= 0 ? 0 : overlap.height / most
        isAbove = row.midY < visible.midY
        top = row.minY - visible.minY
        contentTop = proxy.frame(in: .list).minY
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

    /// Reports this row's height as it changes, while `isOn`.
    func reportingHeight(_ isOn: Bool, to action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat?.self) { proxy in
            isOn ? proxy.size.height : nil
        } action: { height in
            if let height {
                action(height)
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

/// The way back to the current exercise, floating over the list while it is scrolled away: an
/// arrow toward it, and its name.
struct CurrentExerciseButton: View {
    let name: String
    let isAbove: Bool
    let action: () -> Void

    @ObserveHotReload private var hotReload

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isAbove ? "arrow.up" : "arrow.down")
                Text(name)
                    .lineLimit(1)
            }
            .font(.ppButton)
        }
        .buttonStyle(.glass)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Go to current exercise, \(name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workout.current")
        .hotReloadable()
    }
}

extension RoutineExercise {
    /// The row grown into the current exercise, on its first set, its label `minHeight` tall.
    func focus(inSuperset: Bool, minHeight: CGFloat, locale: Locale) -> RowFocus {
        RowFocus(
            progress: progressText(set: 1, inSuperset: inSuperset, locale: locale),
            equipment: [exercise].equipment.map(\.name),
            figures: figures(locale: locale).map { .init(number: $0.number, unit: $0.unit) },
            spokenFigures: spokenFigures(locale: locale),
            minHeight: minHeight,
        )
    }
}
