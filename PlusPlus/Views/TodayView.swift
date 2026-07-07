import SwiftUI
import SwiftData

/// Today, v0 (#109): the tab shell — header with the settings entry and
/// the committed-session record, so history stays reachable while the
/// full unified timeline (pending entries, diffs, the rail) lands with
/// #110. Append-only: no delete affordances, ever.
struct TodayView: View {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
    )
    private var sessions: [WorkoutSession]

    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if sessions.isEmpty {
                    Text("Finished workouts show up here.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "slider.horizontal.3", identifier: "settingsButton") {
                    showingSettings = true
                }
            }
            Text("Today")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
            Text(caption)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var caption: String {
        Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .lowercased()
    }
}
