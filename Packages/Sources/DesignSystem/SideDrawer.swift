import SwiftUI

/// A drawer under the screen: opening it slides the screen right, leaving a sliver of it in
/// view, and a tap on the sliver closes it.
public struct SideDrawer<Drawer: View, Content: View>: View {
    @Binding private var isOpen: Bool
    private let drawer: Drawer
    private let content: Content
    /// How far open, 0 to 1, fixed for a snapshot; nil follows `isOpen`.
    private let progress: CGFloat?
    @ObserveHotReload private var hotReload

    public init(
        isOpen: Binding<Bool>,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(isOpen: isOpen, progress: nil, drawer: drawer, content: content)
    }

    init(
        isOpen: Binding<Bool>,
        progress: CGFloat?,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        _isOpen = isOpen
        self.progress = progress
        self.drawer = drawer()
        self.content = content()
    }

    public var body: some View {
        let progress = progress ?? (isOpen ? 1 : 0)
        GeometryReader { proxy in
            let drawerWidth = max(proxy.size.width - DrawerMetrics.sliver, 0)
            ZStack(alignment: .leading) {
                drawer
                    .frame(width: drawerWidth)
                    .background { Color.pp(.background).ignoresSafeArea() }
                    .accessibilityHidden(!isOpen)
                content
                    .frame(width: proxy.size.width)
                    .allowsHitTesting(!isOpen)
                    .accessibilityHidden(isOpen)
                    .background {
                        Color.pp(.background)
                            .shadow(
                                color: .pp(.shadow).opacity(progress),
                                radius: DrawerMetrics.shadowRadius,
                                x: DrawerMetrics.shadowOffset,
                            )
                            .ignoresSafeArea()
                    }
                    .overlay {
                        if isOpen {
                            Color.clear
                                .contentShape(.rect)
                                .ignoresSafeArea()
                                .onTapGesture { isOpen = false }
                                .accessibilityHidden(true)
                        }
                    }
                    .offset(x: progress * drawerWidth)
            }
        }
        .animation(.snappy(duration: 0.3), value: isOpen)
        .hotReloadable()
    }
}

enum DrawerMetrics {
    /// How much of the screen stays in view beside the open drawer.
    static let sliver: CGFloat = 78
    /// The shadow the screen casts on the drawer, from the design.
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = -14
}

#Preview {
    @Previewable @State var isOpen = true
    SideDrawer(isOpen: $isOpen) {
        Text(verbatim: "Drawer")
    } content: {
        Button("Open") { isOpen = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
