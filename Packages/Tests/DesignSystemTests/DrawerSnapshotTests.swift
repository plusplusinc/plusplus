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

    /// The place showing, which the drawer marks; a routine marks neither.
    private enum Showing: Equatable {
        case routines
        case exercises
        case routine
    }

    /// The drawer as `DrawerMenu` lays it out: the title, then Routines and Exercises.
    private func menu(showing: Showing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: "PlusPlus")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.horizontal, Spacing.sm)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button("Routines", systemImage: "checklist") { }
                    .buttonStyle(.drawer(isSelected: showing == .routines))
                Button { } label: {
                    Label { Text(verbatim: "Exercises") } icon: { CircleStackSymbol() }
                }
                .buttonStyle(.drawer(isSelected: showing == .exercises))
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
    private var routine: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditableTitle(
                text: .constant("Leg day"),
                isEditing: .constant(false),
                placeholder: "New routine",
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
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
            routine
        }
        .frame(height: Self.screenHeight)
    }

    @Test("The drawer open on a routine: Routines and Exercises, neither marked, beside the sliver")
    func routineShowing() {
        assertThemedSnapshots(of: drawer(showing: .routine), width: Self.screenWidth)
    }

    @Test("The drawer open on the Routines screen: Routines is marked")
    func routinesShowing() {
        assertThemedSnapshots(of: drawer(showing: .routines), width: Self.screenWidth)
    }

    @Test("The drawer open on Exercises: Exercises is marked, its stack of circles on the fill")
    func exercisesShowing() {
        assertThemedSnapshots(of: drawer(showing: .exercises), width: Self.screenWidth)
    }

    @Test("Exercises' circle stack stands as tall as checklist, its cutouts showing the fill")
    func circleStack() {
        let pair = HStack(spacing: Spacing.lg) {
            Image(systemName: "checklist")
            CircleStackSymbol()
        }
        .font(.ppDrawerItem)
        .foregroundStyle(.pp(.textPrimary))
        .padding(Spacing.md)
        assertThemedSnapshots(
            of: VStack(spacing: 0) {
                pair.background(Color.pp(.background))
                pair.background(Color.pp(.selectionFill))
            },
            width: 160,
        )
    }

    /// The Routines screen's content as `RoutinesScreen` lays it out, under its bar.
    private func routinesList(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Routines")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.bottom, Spacing.md)
            ForEach(names, id: \.self, content: NameRow.init)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    @Test("The Routines screen: a name per row, a long one wrapping")
    func routinesScreen() {
        assertThemedSnapshots(
            of: routinesList([
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
