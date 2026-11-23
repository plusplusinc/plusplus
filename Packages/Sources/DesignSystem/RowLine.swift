import SwiftUI

/// The line under a row in a list, such as the Workouts and Log lists, drawn as Add exercise's
/// list draws its own: the system's separator, a point thick. Laid over the row's foot, so no row
/// moves for it.
public struct RowLine: View {
    public init() { }

    public var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 0) {
        WorkoutRow("Leg day")
            .overlay(alignment: .bottom) { RowLine() }
        WorkoutRow("Upper body strength and conditioning")
            .overlay(alignment: .bottom) { RowLine() }
    }
    .padding()
    .background(Color.pp(.background))
}
