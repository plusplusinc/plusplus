import CoreGraphics
import Testing
@testable import DesignSystem

@Suite("Swipe to delete")
struct SwipeSettleTests {
    /// A swipe on a closed row, where the finger's travel is the key's offset.
    private static func settle(
        _ offset: CGFloat,
        velocity: CGFloat = 0,
        keyWidth: CGFloat = 88,
    ) -> SwipeSettle {
        SwipeSettle.settle(
            offset: offset,
            travel: offset,
            velocity: velocity,
            width: 300,
            keyWidth: keyWidth,
        )
    }

    /// A swipe on an open row, whose key starts drawn in by its width.
    private static func settleOpen(travel: CGFloat, velocity: CGFloat) -> SwipeSettle {
        SwipeSettle.settle(
            offset: -88 + travel,
            travel: travel,
            velocity: velocity,
            width: 300,
            keyWidth: 88,
        )
    }

    @Test("A swipe settles closed, open, or deleted")
    func settle() {
        #expect(Self.settle(-20) == .closed)
        #expect(Self.settle(-100) == .open)
        #expect(Self.settle(-170) == .open)
        #expect(Self.settle(-190) == .delete)
        #expect(Self.settle(-88, velocity: 1500) == .closed)
        #expect(Self.settle(-88, velocity: -200) == .open)
    }

    @Test("A short fast flick opens the key and never deletes")
    func flickOpens() {
        #expect(Self.settle(0, velocity: -3868) == .open)
        #expect(Self.settle(-30, velocity: -1500) == .open)
        #expect(Self.settle(-170, velocity: -5000) == .open)
        #expect(Self.settleOpen(travel: -20, velocity: -3868) == .open)
        // The key and the finger together pass twice the key's width; the finger alone does not.
        #expect(Self.settleOpen(travel: -90, velocity: -1500) == .open)
    }

    @Test("A drag right on an open row closes it, however short or slow")
    func dragRightCloses() {
        #expect(Self.settleOpen(travel: 20, velocity: 0) == .closed)
        #expect(Self.settleOpen(travel: 40, velocity: 150) == .closed)
        #expect(Self.settleOpen(travel: 100, velocity: 300) == .closed)
    }

    @Test("A fast swipe well past the key deletes")
    func fastSwipeDeletes() {
        #expect(Self.settle(-177, velocity: -1500) == .delete)
    }

    @Test("A row whose key covers most of it opens rather than deletes at rest")
    func wideKey() {
        // At the largest text sizes the key is wider than half the row.
        #expect(Self.settle(-200, keyWidth: 200) == .open)
        #expect(Self.settle(-220, velocity: -1500, keyWidth: 200) == .open)
        #expect(Self.settle(-301, keyWidth: 200) == .delete)
    }
}
