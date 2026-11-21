// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The ++ drawer open over a routine, and the Routines screen's list, built from the components
/// the app composes them from. The drawer's menu and the Routines screen live in the app, which
/// has no test target; their bars, and the drawer's motion, are checked on the simulator.
@Suite("Drawer")
struct DrawerSnapshotTests {
    private static let screenWidth: CGFloat = 390
    /// An iPhone's height, so the drawer and the screen beside it are drawn whole.
    private static let screenHeight: CGFloat = 844

    /// The place showing, which the drawer marks; a routine marks nothing.
    private enum Showing: Equatable {
        case workouts
        case workout
    }

    /// The drawer as `DrawerMenu` lays it out: the title, then Routines.
    private func menu(showing: Showing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: "PlusPlus")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.horizontal, Spacing.sm)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button("Workouts", systemImage: "checklist") { }
                    .buttonStyle(.drawer(isSelected: showing == .workouts))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private struct Row: Identifiable {
        let id = UUID()
        let name: String
    }

    private static let rows = [Row(name: "Goblet squat"), Row(name: "Romanian deadlift")]

    /// A routine screen behind, slid aside to its sliver.
    private var workout: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditableTitle(
                text: .constant("Leg day"),
                isEditing: .constant(false),
                placeholder: "New workout",
                accessibilityLabel: "Workout name",
                accessibilityHint: "Renames the workout.",
            )
            Rail(Self.rows) { row in
                RowLabel(title: row.name, detail: ["3 × 10 reps", "35 lb"])
                    .railRow()
            } end: {
                FloatingButtonRoom()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pp(.background))
    }

    private func drawer(showing: Showing) -> some View {
        SideDrawer(isOpen: .constant(true), progress: 1) {
            menu(showing: showing)
        } content: {
            workout
        }
        .frame(height: Self.screenHeight)
    }

    @Test("The drawer open on a routine: Routines, unmarked, beside the sliver")
    func workoutShowing() {
        assertThemedSnapshots(of: drawer(showing: .workout), width: Self.screenWidth)
    }

    @Test("The drawer open on the Routines screen: Routines is marked")
    func workoutsShowing() {
        assertThemedSnapshots(of: drawer(showing: .workouts), width: Self.screenWidth)
    }

    /// The Routines screen's content as `WorkoutsScreen` lays it out, under its bar.
    private func workoutsList(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Workouts")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            ForEach(names, id: \.self) { name in
                NameRow(name)
                    .padding(.horizontal, Spacing.md)
                    .overlay(alignment: .bottom) { RowLine().padding(.horizontal, Spacing.md) }
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    @Test("The Routines screen: a name per row under a line, a long one wrapping")
    func workoutsScreen() {
        assertThemedSnapshots(
            of: workoutsList([
                "Leg day",
                "Upper body strength, conditioning, and mobility",
                "Chest and back",
                "Core",
            ]),
            width: Self.screenWidth,
        )
    }
}

#endif
