import SwiftUI

extension View {
    /// Draws a control that makes something in green, as the + that adds an exercise is filled:
    /// Add exercise's Create row and the Routines screen's New routine +. Sets both the tint, which
    /// a bar's button draws its icon in, and the foreground, which a row's label draws in. The
    /// drawer's New stays in its own color, so the drawer's places read as one list.
    public func makesSomething() -> some View {
        tint(.pp(.accent)).foregroundStyle(.pp(.accent))
    }
}

#Preview {
    Label("Create \u{201C}Zercher squat\u{201D}", systemImage: "plus")
        .font(.ppRowTitle)
        .makesSomething()
        .padding()
        .background(Color.pp(.background))
}
