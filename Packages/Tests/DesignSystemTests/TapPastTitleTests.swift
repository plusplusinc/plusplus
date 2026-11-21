import Testing
@testable import DesignSystem

@Suite("A tap past the title does what it does with the keyboard down")
struct TapPastTitleTests {
    /// A touch that ends the title's edit with the keyboard up.
    private func endingEdit() -> TapPastTitle {
        var tap = TapPastTitle()
        tap.keyboardWillShow()
        tap.touchDown(onTitle: false, endingEdit: true)
        return tap
    }

    @Test("At rest, a tap acts at once; on the title, never")
    func atRest() {
        var tap = TapPastTitle()
        tap.touchDown(onTitle: false, endingEdit: false)
        let outside = tap.tap(actsAfterEdit: false)
        tap.touchDown(onTitle: true, endingEdit: false)
        let onTitle = tap.tap(actsAfterEdit: true)
        #expect(outside)
        #expect(!onTitle)
    }

    @Test("A tap that ends the edit acts only once the keyboard is all the way down")
    func actsOnceKeyboardIsDown() {
        var tap = endingEdit()
        let atTap = tap.tap(actsAfterEdit: true)
        #expect(!atTap, "It acted with the keyboard still up")
        let atHide = tap.keyboardDidHide()
        let atSecondHide = tap.keyboardDidHide()
        #expect(atHide, "The keyboard went down and the tap never acted")
        #expect(!atSecondHide, "One tap acted twice")
    }

    @Test("A tap that ends the edit with no keyboard up acts at once")
    func actsAtOnceWithNoKeyboard() {
        var tap = TapPastTitle()
        tap.touchDown(onTitle: false, endingEdit: true)
        let acts = tap.tap(actsAfterEdit: true)
        #expect(acts)
        #expect(!tap.isWaiting)
    }

    @Test("A place that acts only at rest has only ended the edit")
    func onlyEndsEdit() {
        var tap = endingEdit()
        let atTap = tap.tap(actsAfterEdit: false)
        let atHide = tap.keyboardDidHide()
        #expect(!atTap)
        #expect(!atHide, "The keyboard's going acted for a tap that only ended the edit")
    }

    @Test("A new touch drops what an earlier tap left waiting")
    func newTouchDropsWait() {
        for onTitle in [true, false] {
            var tap = endingEdit()
            _ = tap.tap(actsAfterEdit: true)
            tap.touchDown(onTitle: onTitle, endingEdit: false)
            let atHide = tap.keyboardDidHide()
            #expect(!atHide, "A waiting tap acted after a new touch")
        }
    }
}
