import Foundation
import Testing
@testable import DesignSystem

struct WaitShownTests {
    private static let locale = Locale(identifier: "en_US")

    /// What a countdown of `kind`, 10 s long, reads with `left` seconds to go, held there.
    private static func reads(_ kind: SetRest.Kind, left: Double) -> String {
        let block = RestBlock(stage: .open, length: 10, pausedLeft: left)
        return RestBlock.text(
            block.left(at: .now, within: kind.shown(length: 10)),
            locale: locale,
        )
    }

    @Test("Starts in never reads 0:00, and reads 0:10 while its count has not yet begun")
    func startsIn() {
        let kind = SetRest.Kind.startsIn(time: "30 seconds")
        #expect(Self.reads(kind, left: 0) == "0:01")
        #expect(Self.reads(kind, left: 0.4) == "0:01")
        // Counting from after the slot comes in: 10.3 s to go as it fades in.
        #expect(Self.reads(kind, left: 10.3) == "0:10")
        #expect(Self.reads(kind, left: 9.2) == "0:10")
    }

    @Test("A rest and a set's count read 0:00 at their end and never cap")
    func others() {
        #expect(Self.reads(.rest, left: 0) == "0:00")
        #expect(Self.reads(.count, left: 0) == "0:00")
        #expect(Self.reads(.rest, left: 10.3) == "0:11")
    }
}
