import SwiftUI
import Testing
@testable import DesignSystem

/// Where a drawer comes to rest when what keeps `isOpen` may refuse an open, as the routine's
/// session does once a row's sheet has been asked for.
@Suite("Drawer settle")
@MainActor
struct DrawerSettleTests {
    /// A keeper of `isOpen` that refuses every open.
    private final class Refusing {
        var isOpen = false
    }

    @Test("An open the keeper refuses settles the drawer closed")
    func refusedOpenSettlesClosed() {
        let keeper = Refusing()
        let isOpen = Binding { keeper.isOpen } set: { _ in }
        #expect(!settledSide(asking: true, of: isOpen))
        #expect(!keeper.isOpen)
    }

    @Test("An open the keeper allows, and any close, settle where asked")
    func allowedSettlesWhereAsked() {
        var isOpen = false
        let binding = Binding { isOpen } set: { isOpen = $0 }
        #expect(settledSide(asking: true, of: binding))
        #expect(!settledSide(asking: false, of: binding))
    }
}
