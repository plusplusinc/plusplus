import SwiftUI

/// A row that makes something new from what was typed, such as Create "Zercher squat" under the
/// Add exercise search: a + and its title, both green, as the + that adds an exercise is, so
/// making something reads apart from the rows that pick what exists.
public struct CreateLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Label(title, systemImage: "plus")
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.accent))
    }
}

#Preview {
    CreateLabel("Create \u{201C}Zercher squat\u{201D}")
        .padding()
        .background(Color.pp(.background))
}
