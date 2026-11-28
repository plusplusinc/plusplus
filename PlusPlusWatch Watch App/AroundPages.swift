#if canImport(Session)
import DesignSystem
import SwiftUI
import WorkoutStore

/// The left page: the workout's name, its time, how far through it is, and Pause and End.
struct TimePage: View {
    let page: WatchTimePage
    let pause: () -> Void
    let end: () -> Void

    var body: some View {
        WatchScreen {
            VStack(alignment: .leading, spacing: 0) {
                Text(page.name)
                    .ppWatchFont(.caption)
                    .foregroundStyle(Color.pp(.textSecondary))
                    .lineLimit(1)
                    .clearOfClock()
                ShrunkToFit { scale in
                    Text(page.time)
                        .ppWatchDigits(.time, scale: scale)
                        .foregroundStyle(Color.pp(page.isPaused ? .textSecondary : .textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.top, 15)
                .padding(.bottom, 7)
                Text(page.progress)
                    .ppWatchFont(.unit)
                    .foregroundStyle(Color.pp(.textSecondary))
                    .lineLimit(1)
            }
        } keys: {
            HStack(spacing: 5) {
                WatchKey(page.isPaused ? "Continue" : "Pause", isSmall: true, action: pause)
                WatchKey("End", isSmall: true, action: end)
            }
        }
    }
}

/// End's choice: Finish as the key, Discard quieter in red over it; with nothing logged, Discard
/// alone, as on the phone (`WorkoutSession.offersFinish`). Swiping to another page puts it away.
struct EndChoicePage: View {
    let offersFinish: Bool
    let finish: () -> Void
    let discard: () -> Void

    var body: some View {
        WatchScreen {
            VStack(alignment: .leading, spacing: 4) {
                Text("End workout?")
                    .ppWatchFont(.title)
                    .foregroundStyle(Color.pp(.textPrimary))
                    .clearOfClock()
                Text(offersFinish ? "Finish keeps what you logged." : "Nothing is logged yet.")
                    .ppWatchFont(.body)
                    .foregroundStyle(Color.pp(.textSecondary))
            }
        } keys: {
            VStack(spacing: 0) {
                Button("Discard workout", role: .destructive, action: discard)
                    .buttonStyle(.plain)
                    .ppWatchFont(.textButton)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                if offersFinish {
                    WatchKey("Finish", isPrimary: true, action: finish)
                }
            }
        }
    }
}

/// The right page: the whole workout, scrolled with the crown, opening on the current row. Each
/// row's detail is one line, its plan as its values read (`WorkoutExercise.value(of:locale:)`),
/// cut short at its end if it must be.
struct ListPage: View {
    let name: String
    let rows: [WatchListRow]

    var body: some View {
        WholeScreen { _, _ in
            rowList
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    Text(name)
                        .ppWatchFont(.caption)
                        .foregroundStyle(Color.pp(.textSecondary))
                        .lineLimit(1)
                        .clearOfClock()
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle()
                                .fill(color(of: row.dot))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name)
                                    .ppWatchFont(.rowName)
                                    .foregroundStyle(Color.pp(
                                        row.dot == .done ? .textSecondary : .textPrimary,
                                    ))
                                    .lineLimit(1)
                                Text(row.detail)
                                    .ppWatchFont(.rowDetail)
                                    .foregroundStyle(Color.pp(.textSecondary))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .id(row.id)
                    }
                }
                .padding(.horizontal, WatchPage.sideInset)
                .padding(.top, WatchPage.topInset)
                .padding(.bottom, WatchPage.listFoot)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if let current = rows.first(where: { $0.dot == .current }) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }

    private func color(of dot: WatchListRow.Dot) -> Color {
        switch dot {
        case .done: .pp(.done)
        case .current: .pp(.accent)
        case .toDo: .pp(.toDo)
        }
    }
}

/// After a finish: the "++", the workout's name, one line, and Done.
struct FinishedPage: View {
    let end: LinkEnd
    let done: () -> Void

    var body: some View {
        WatchScreen {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "++")
                    .ppWatchFont(.mark)
                    .foregroundStyle(Color.pp(.accent))
                    .accessibilityHidden(true)
                Text(end.name)
                    .ppWatchFont(.title)
                    .foregroundStyle(Color.pp(.textPrimary))
                    .lineLimit(1)
                    .padding(.top, 6)
                Text(end.summary())
                    .ppWatchFont(.caption)
                    .foregroundStyle(Color.pp(.textSecondary))
                    .padding(.top, 2)
            }
        } keys: {
            WatchKey("Done", isPrimary: true, action: done)
        }
    }
}
#endif
