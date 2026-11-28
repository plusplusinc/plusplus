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
        VStack(alignment: .leading, spacing: 0) {
            Text(page.name)
                .ppWatchFont(.caption)
                .foregroundStyle(Color.pp(.textSecondary))
                .lineLimit(1)
            Text(page.time)
                .ppWatchFont(.time)
                .foregroundStyle(Color.pp(page.isPaused ? .textSecondary : .textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)
            Text(page.progress)
                .ppWatchFont(.body)
                .foregroundStyle(Color.pp(.textSecondary))
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                WatchKey(page.isPaused ? "Continue" : "Pause", isSmall: true, action: pause)
                WatchKey("End", isSmall: true, action: end)
            }
            .frame(height: WatchKey.height)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, WatchPage.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// End's choice: Finish as the key, Discard quieter in red; with nothing logged, Discard alone,
/// as on the phone (`WorkoutSession.offersFinish`). Swiping to another page puts it away.
struct EndChoicePage: View {
    let offersFinish: Bool
    let finish: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("End workout?")
                .ppWatchFont(.title)
                .foregroundStyle(Color.pp(.textPrimary))
            Text(offersFinish ? "Finish keeps what you logged." : "Nothing is logged yet.")
                .ppWatchFont(.body)
                .foregroundStyle(Color.pp(.textSecondary))
                .padding(.top, 2)
            Spacer(minLength: 6)
            Button("Discard workout", role: .destructive, action: discard)
                .buttonStyle(.plain)
                .ppWatchFont(.textButton)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            if offersFinish {
                WatchKey("Finish", isPrimary: true, action: finish)
                    .frame(height: WatchKey.height)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, WatchPage.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The right page: the whole workout, scrolled with the crown, opening on the current row.
struct ListPage: View {
    let name: String
    let rows: [WatchListRow]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(name)
                        .ppWatchFont(.caption)
                        .foregroundStyle(Color.pp(.textSecondary))
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
                                Text(row.detail)
                                    .ppWatchFont(.caption)
                                    .foregroundStyle(Color.pp(.textSecondary))
                            }
                        }
                        .id(row.id)
                    }
                }
                .padding(.horizontal, WatchPage.sideInset)
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
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "++")
                .ppWatchFont(.mark)
                .foregroundStyle(Color.pp(.accent))
                .accessibilityHidden(true)
            Text(end.name)
                .ppWatchFont(.title)
                .foregroundStyle(Color.pp(.textPrimary))
                .padding(.top, 6)
            Text(end.summary())
                .ppWatchFont(.caption)
                .foregroundStyle(Color.pp(.textSecondary))
                .padding(.top, 2)
            Spacer(minLength: 6)
            WatchKey("Done", isPrimary: true, action: done)
                .frame(height: WatchKey.height)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, WatchPage.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
