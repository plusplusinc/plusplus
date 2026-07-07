import SwiftUI
import SwiftData

/// The one slide-to-reveal quick-actions affordance (#88): trailing
/// mono-label buttons behind the row. Horizontal-dominant drags reveal;
/// vertical movement stays with the surrounding scroll. One row open at
/// a time via the shared `openRow` binding.
struct SwipeRevealRow<Content: View, Actions: View>: View {
    let id: PersistentIdentifier
    @Binding var openRow: PersistentIdentifier?
    var enabled: Bool = true
    let actionsWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    @State private var dragX: CGFloat = 0

    private var restingOffset: CGFloat {
        openRow == id ? -actionsWidth : 0
    }

    private var offset: CGFloat {
        min(0, max(restingOffset + dragX, -actionsWidth - 24))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions()
                .frame(width: actionsWidth)
                .frame(maxHeight: .infinity)
                .opacity(offset < -12 ? 1 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            guard enabled,
                                  abs(value.translation.width) > abs(value.translation.height)
                            else { return }
                            dragX = value.translation.width
                        }
                        .onEnded { value in
                            guard enabled else { return }
                            if dragX != 0 {
                                let projected = restingOffset + value.predictedEndTranslation.width
                                openRow = projected < -actionsWidth / 2 ? id : (openRow == id ? nil : openRow)
                            }
                            dragX = 0
                        }
                )
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: offset)
    }
}

/// One action inside a SwipeRevealRow: 58 pt, mono uppercase label.
struct SwipeActionButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.border), alignment: .leading)
        }
    }
}
