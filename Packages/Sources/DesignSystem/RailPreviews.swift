import SwiftUI

private let previewRows = [
    PreviewRow(title: "Goblet squat", detail: "Kettlebell"),
    PreviewRow(title: "Push-up", detail: nil),
    PreviewRow(title: "Farmer\u{2019}s carry", detail: "Dumbbells"),
    PreviewRow(title: "Plank", detail: "60 s"),
]

private func previewRail(drag: RailDragState<UUID>? = nil, cardTop: CGFloat = 0) -> some View {
    Rail(previewRows, drag: drag, cardTop: cardTop) { exercise in
        RowLabel(title: exercise.title, detail: exercise.detail).railRow()
    } end: {
        Button("Add exercise", systemImage: "plus") { }
            .buttonStyle(.key)
    }
    .padding()
    .background(Color.pp(.background))
}

#Preview {
    previewRail()
}

#Preview("Lifted at its place") {
    let lifted = previewRows[1]
    previewRail(drag: RailDragState(
        lifted: lifted.id,
        origin: .before(previewRows[2].id),
        slot: .before(previewRows[2].id),
        grab: 20,
    ), cardTop: 64)
}

#Preview("Gap two rows down") {
    let lifted = previewRows[1]
    previewRail(drag: RailDragState(
        lifted: lifted.id,
        origin: .before(previewRows[2].id),
        slot: .end,
        grab: 20,
    ), cardTop: 180)
}

private struct PreviewRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
}
