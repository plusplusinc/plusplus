import SwiftUI

/// A row in a list of names, such as the Routines screen's: the name in SF Pro, as it can't be
/// edited there, across the list's width, at a comfortable tap height. The whole row takes taps.
public struct NameRow: View {
    private let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var body: some View {
        // A later card will put the routine's schedule trailing, beside the name.
        Text(name)
            .font(.ppWorkoutName)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
    }
}

/// The line under a row in a list of names, drawn as Add exercise's list draws its own: the
/// system's separator, a point thick. Laid over the row's foot, so no row moves for it.
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
        NameRow("Leg day")
            .overlay(alignment: .bottom) { RowLine() }
        NameRow("Upper body strength and conditioning")
            .overlay(alignment: .bottom) { RowLine() }
    }
    .padding()
    .background(Color.pp(.background))
}
