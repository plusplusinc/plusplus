import SwiftUI

/// v3 navigation root (#109): four bottom tabs — Today · Workouts ·
/// Exercises · Equipment. Creation is contextual (each tab's header +
/// creates its own thing); the FAB menu and the History destination are
/// gone (Today's timeline subsumes history, #110).
struct RootTabView: View {
    enum AppTab: String, CaseIterable {
        case today, workouts, exercises, equipment

        var label: String { rawValue }
    }

    @State private var tab: AppTab = .today
    @AppStorage(OnboardingView.completedKey) private var onboardingComplete = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .today: TodayView(onGoToWorkouts: { tab = .workouts })
                case .workouts: WorkoutListView()
                case .exercises: ExercisesTabView()
                case .equipment: EquipmentTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.background)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingComplete },
            set: { presented in if !presented { onboardingComplete = true } }
        )) {
            OnboardingView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { candidate in
                let active = tab == candidate
                Button {
                    tab = candidate
                } label: {
                    VStack(spacing: 3) {
                        TabIcon(tab: candidate, active: active)
                            .frame(width: 22, height: 22)
                        Text(candidate.label)
                            .font(.system(.caption2, design: .monospaced, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("tab-\(candidate.rawValue)")
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}

/// The four tab glyphs, drawn to match the prototype: Today is a commit
/// node (dashed above — the staged part — solid below), Workouts is two
/// stacked cards, Exercises a list with rail dots, Equipment the SF
/// dumbbell.
private struct TabIcon: View {
    let tab: RootTabView.AppTab
    let active: Bool

    var body: some View {
        switch tab {
        case .today:
            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2
                var dashed = Path()
                dashed.move(to: CGPoint(x: cx, y: 0))
                dashed.addLine(to: CGPoint(x: cx, y: cy - 5))
                context.stroke(dashed, with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2.5]))
                var solid = Path()
                solid.move(to: CGPoint(x: cx, y: cy + 5))
                solid.addLine(to: CGPoint(x: cx, y: size.height))
                context.stroke(solid, with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5))
                let node = CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)
                if active {
                    context.fill(Path(ellipseIn: node), with: .style(.foreground))
                } else {
                    context.stroke(Path(ellipseIn: node), with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5))
                }
            }
        case .workouts:
            Canvas { context, size in
                let back = CGRect(x: 4, y: 2, width: size.width - 8, height: 8)
                let front = CGRect(x: 2, y: 9, width: size.width - 4, height: 10)
                context.stroke(Path(roundedRect: back, cornerRadius: 2.5), with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5))
                context.fill(Path(roundedRect: front, cornerRadius: 2.5), with: .color(Theme.background))
                context.stroke(Path(roundedRect: front, cornerRadius: 2.5), with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5))
            }
        case .exercises:
            Canvas { context, size in
                for (i, y) in [4.0, 11.0, 18.0].enumerated() {
                    let dot = CGRect(x: 2, y: y - 1.75, width: 3.5, height: 3.5)
                    if i == 0 && active {
                        context.fill(Path(ellipseIn: dot), with: .style(.foreground))
                    } else {
                        context.stroke(Path(ellipseIn: dot), with: .style(.foreground), style: StrokeStyle(lineWidth: 1.2))
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: 9, y: y))
                    line.addLine(to: CGPoint(x: size.width - 1, y: y))
                    context.stroke(line, with: .style(.foreground), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        case .equipment:
            Image(systemName: "dumbbell")
                .font(.system(size: 15, weight: active ? .semibold : .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The ++ glyph anchoring every tab header, top-left — the one place
/// the brand green appears in chrome.
struct HeaderGlyph: View {
    var body: some View {
        Text("++")
            .font(.system(.subheadline, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
    }
}
