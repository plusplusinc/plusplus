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
            .font(.ppRoutineName)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
    }
}

#Preview {
    VStack(spacing: 0) {
        NameRow("Leg day")
        NameRow("Upper body strength and conditioning")
    }
    .padding()
    .background(Color.pp(.background))
}
