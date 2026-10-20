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

    /// The place showing, which the drawer marks.
    private enum Showing: Equatable {
        case routines
        case routine(String)
        case new
    }

    /// The drawer as `DrawerMenu` lays it out: the title, Routines, then each routine with its
    /// node, a new one showing first, in the placeholder's gray, and New, never marked.
    private func menu(routines: [String], showing: Showing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: "PlusPlus")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.horizontal, Spacing.sm)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button("Routines", systemImage: "rectangle.stack") { }
                    .buttonStyle(.drawer(isSelected: showing == .routines))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if showing == .new {
                        Button { } label: {
                            Label {
                                Text("New routine").foregroundStyle(.pp(.textSecondary))
                            } icon: {
                                DrawerNode(isLit: true)
                            }
                        }
                        .buttonStyle(.drawer(isSelected: true, isNested: true))
                    }
                    ForEach(routines, id: \.self) { name in
                        let isShowing = showing == .routine(name)
                        Button { } label: {
                            Label { Text(name) } icon: { DrawerNode(isLit: isShowing) }
                        }
                        .buttonStyle(.drawer(isSelected: isShowing, isNested: true))
                    }
                    Button("New", systemImage: "plus") { }
                        .buttonStyle(.drawer(isSelected: false, isNested: true))
                }
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
                Button("Add exercise", systemImage: "plus") { }
                    .buttonStyle(.key)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pp(.background))
    }

    private func drawer(routines: [String], showing: Showing) -> some View {
        SideDrawer(isOpen: .constant(true), progress: 1) {
            menu(routines: routines, showing: showing)
        } content: {
            routine
        }
        .frame(height: Self.screenHeight)
    }

    @Test("The drawer open on a routine: it is marked, its node lit, beside the sliver")
    func routineShowing() {
        assertThemedSnapshots(
            of: drawer(routines: ["Leg day", "Upper body", "Core"], showing: .routine("Leg day")),
            width: Self.screenWidth,
        )
    }

    @Test("The drawer open on the Routines screen: Routines is marked")
    func routinesShowing() {
        assertThemedSnapshots(
            of: drawer(routines: ["Leg day", "Upper body", "Core"], showing: .routines),
            width: Self.screenWidth,
        )
    }

    @Test("The drawer open on a new routine: its gray row is marked, above the two latest")
    func newShowing() {
        assertThemedSnapshots(
            of: drawer(routines: ["Leg day", "Upper body"], showing: .new),
            width: Self.screenWidth,
        )
    }

    /// The Routines screen's content as `RoutinesScreen` lays it out, under its bar.
    private func routinesList(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Routines")
                .ppFixedTitleFont()
                .foregroundStyle(.pp(.textPrimary))
                .padding(.bottom, Spacing.md)
            ForEach(names, id: \.self) { name in
                if name != names.first {
                    Hairline()
                }
                NameRow(name)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    @Test("The Routines screen: a name per row, between hairlines, a long one wrapping")
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
