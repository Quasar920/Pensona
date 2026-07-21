import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RootPresentationStateTests: XCTestCase {
    func testRapidNewEntryRequestsCreateOnlyOneSession() {
        let state = RootPresentationState()
        state.presentNewEntry()
        let firstID = state.entry?.id
        for _ in 0..<20 { state.presentNewEntry() }
        XCTAssertEqual(state.entry?.id, firstID)
    }

    func testExternalDraftCannotBeOverwrittenByOrdinaryEntry() {
        let state = RootPresentationState()
        let draft = TransactionDraft(type: .expense, amount: 12, sourceWallet: nil)
        state.presentExternalEntry(draft)
        let firstID = state.entry?.id
        state.presentNewEntry()
        XCTAssertEqual(state.entry?.id, firstID)
        guard case let .external(savedDraft)? = state.entry?.mode else {
            return XCTFail("Expected external route")
        }
        XCTAssertEqual(savedDraft.amount, 12)
    }

    func testSecondExternalRequestDoesNotReplaceActiveSession() {
        let state = RootPresentationState()
        state.presentExternalEntry(TransactionDraft(type: .income, amount: 8, sourceWallet: nil))
        let firstID = state.entry?.id
        state.presentExternalEntry(TransactionDraft(type: .expense, amount: 99, sourceWallet: nil))
        XCTAssertEqual(state.entry?.id, firstID)
    }

    func testDismissalIsTheOnlyOperationThatClearsSession() {
        let state = RootPresentationState()
        state.presentNewEntry()
        XCTAssertTrue(state.isPresentingEntry)
        state.finishDismissal()
        XCTAssertFalse(state.isPresentingEntry)
    }

    func testTwentySequentialOpenCloseCyclesLeaveNoStaleSession() {
        let state = RootPresentationState()
        var sessionIDs = Set<UUID>()

        for _ in 0..<20 {
            state.presentNewEntry()
            guard let id = state.entry?.id else {
                return XCTFail("Expected a live entry session")
            }
            XCTAssertTrue(sessionIDs.insert(id).inserted)
            state.finishDismissal()
            XCTAssertFalse(state.isPresentingEntry)
        }

        XCTAssertEqual(sessionIDs.count, 20)
    }

    func testFormUnsavedSignalIgnoresDefaultSelectionsButTracksContent() {
        var form = TransactionFormState()
        form.sourceWalletID = UUID()
        form.categoryID = UUID()
        XCTAssertFalse(form.hasUserEnteredContent)
        form.amountText = "12"
        XCTAssertTrue(form.hasUserEnteredContent)
        form.resetForContinuousEntry()
        XCTAssertFalse(form.hasUserEnteredContent)
    }
}
