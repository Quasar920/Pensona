import XCTest
@testable import MultiCurrencyLedger

final class CenteredGenieCardPresentationTests: XCTestCase {
    func testPresentationMovesFromSourceToCenteredCardAndBack() {
        var state = CenteredGenieCardPresentation()
        let source = CGRect(x: 18, y: 52, width: 136, height: 44)
        let target = CGRect(x: 21, y: 278, width: 360, height: 252)

        state.present(from: source)
        XCTAssertEqual(state.phase, .preparing)
        XCTAssertEqual(state.progress, 1)

        state.beginOpening(to: target)
        XCTAssertEqual(state.phase, .opening)
        state.progress = 0
        state.finishOpening()
        XCTAssertTrue(state.isPresented)

        state.requestDismissal()
        XCTAssertNotNil(state.dismissalRequestID)
        state.beginClosing()
        XCTAssertEqual(state.phase, .closing)
        state.progress = 1
        state.finishClosing()

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.progress, 1)
        XCTAssertTrue(state.sourceFrame.isEmpty)
    }

    func testIgnoresRepeatedPresentationsAndDismissalsOutsidePresentedState() {
        var state = CenteredGenieCardPresentation()
        state.requestDismissal()
        XCTAssertNil(state.dismissalRequestID)

        state.present(from: CGRect(x: 0, y: 0, width: 44, height: 44))
        state.present(from: CGRect(x: 80, y: 80, width: 44, height: 44))
        XCTAssertEqual(state.sourceFrame, CGRect(x: 0, y: 0, width: 44, height: 44))

        state.beginClosing()
        XCTAssertEqual(state.phase, .preparing)
    }
}
