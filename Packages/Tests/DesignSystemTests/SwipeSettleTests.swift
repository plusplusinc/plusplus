import CoreGraphics
import Testing
@testable import DesignSystem

@Suite("Swipe to delete")
struct SwipeSettleTests {
    private static func settle(_ offset: CGFloat, velocity: CGFloat = 0) -> SwipeSettle {
        SwipeSettle.settle(offset: offset, velocity: velocity, width: 300, keyWidth: 88)
    }

    @Test("A swipe settles closed, open, or deleted")
    func settle() {
        #expect(Self.settle(-20) == .closed)
        #expect(Self.settle(-100) == .open)
        #expect(Self.settle(-160) == .delete)
        #expect(Self.settle(-30, velocity: -1500) == .delete)
        #expect(Self.settle(-88, velocity: 1500) == .closed)
        #expect(Self.settle(0, velocity: -1500) == .delete)
        #expect(Self.settle(-88, velocity: -200) == .open)
    }
}
