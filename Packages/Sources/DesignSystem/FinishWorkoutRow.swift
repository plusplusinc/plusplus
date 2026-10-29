import SwiftUI

/// The end of a workout's list once every planned set is logged: a square key with a plus, Add
/// exercise, its plus on the rail where Add exercise's sits, and Finish workout beside it, wide,
/// in the primary key's colors. Both are a key's height.
public struct FinishWorkoutRow: View {
    private let add: () -> Void
    private let finish: () -> Void

    /// A key's height, as Add exercise's at rest.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 48
    @ObserveHotReload private var hotReload

    public init(add: @escaping () -> Void, finish: @escaping () -> Void) {
        self.add = add
        self.finish = finish
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.ppButton)
                    .foregroundStyle(.pp(.textPrimary))
                    .frame(width: height, height: height)
                    .background(keyShape.fill(.pp(.surface)))
                    .overlay(keyShape.strokeBorder(.pp(.borderStrong)))
                    .contentShape(keyShape)
            }
            .buttonStyle(DimmedPress())
            .accessibilityLabel("Add exercise")
            Button(action: finish) {
                Text("Finish workout")
                    .font(.ppPrimaryKey)
                    .foregroundStyle(.pp(.onPrimaryKey))
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(keyShape.fill(.pp(.primaryKey)))
                    .contentShape(keyShape)
            }
            .buttonStyle(DimmedPress())
            .accessibilityIdentifier("workout.finish")
        }
        .hotReloadable()
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.key)
    }
}

/// A key's press, dimmed, so nothing around it moves.
private struct DimmedPress: ButtonStyle {
    @ObserveHotReload private var hotReload

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .keyPress(isPressed: configuration.isPressed)
            .hotReloadable()
    }
}

#Preview {
    FinishWorkoutRow { } finish: { }
        .padding()
        .background(Color.pp(.background))
}
