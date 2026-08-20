import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class EntryContextPresentationStateTests: XCTestCase {
    func testDiscountDraftCommitsOnlyAfterClosingFinishes() {
        let wallet = makeWallet(name: "银行卡")
        var form = TransactionFormState(kind: .expense)
        form.sourceWalletID = wallet.id
        var presentation = preparedPresentation(
            kind: .discount,
            form: form,
            wallets: [wallet]
        )

        presentation.draft?.discountAmountText = "12.5"
        presentation.beginClosing(intent: .commit)

        XCTAssertEqual(form.discountAmountText, "")

        presentation.finishClosing(state: &form)

        XCTAssertEqual(form.discountAmountText, "12.5")
        XCTAssertEqual(presentation.phase, .closed)
    }

    func testSplitPaymentCancelDiscardsDraftKeyboardInput() {
        let first = makeWallet(name: "主卡")
        let second = makeWallet(name: "备用卡")
        var form = TransactionFormState(kind: .expense)
        form.sourceWalletID = first.id
        var presentation = preparedPresentation(
            kind: .splitPayment,
            form: form,
            wallets: [first, second]
        )

        XCTAssertEqual(presentation.draft?.paymentParts.count, 2)
        presentation.draft?.paymentParts[0].amountText = "88"
        presentation.beginClosing(intent: .cancel)
        presentation.finishClosing(state: &form)

        XCTAssertFalse(form.usesSplitPayment)
        XCTAssertTrue(form.paymentParts.isEmpty)
    }

    func testAACancelKeepsMainAmountButDiscardsAASettings() {
        let wallet = makeWallet(name: "银行卡")
        var form = TransactionFormState(kind: .expense)
        form.sourceWalletID = wallet.id
        form.amountText = "20"
        var presentation = preparedPresentation(
            kind: .aa,
            form: form,
            wallets: [wallet]
        )

        presentation.draft?.aaPeople = 4
        form.amountText = "40"
        presentation.beginClosing(intent: .cancel)
        presentation.finishClosing(state: &form)

        XCTAssertEqual(form.amountText, "40")
        XCTAssertNil(form.aaSplitDraft)
    }

    func testAllGenieContextsKeepUsingTheKeypad() {
        let wallet = makeWallet(name: "银行卡")
        let form = TransactionFormState(kind: .expense)

        let aa = preparedPresentation(
            kind: .aa,
            form: form,
            wallets: [wallet]
        )
        let splitPayment = preparedPresentation(
            kind: .splitPayment,
            form: form,
            wallets: [wallet]
        )
        let discount = preparedPresentation(
            kind: .discount,
            form: form,
            wallets: [wallet]
        )

        XCTAssertTrue(aa.usesKeypad)
        XCTAssertTrue(splitPayment.usesKeypad)
        XCTAssertTrue(discount.usesKeypad)
    }

    func testAAUsesPeopleAsTheDefaultKeypadInputTarget() {
        let wallet = makeWallet(name: "银行卡")
        let form = TransactionFormState(kind: .expense)
        let presentation = preparedPresentation(
            kind: .aa,
            form: form,
            wallets: [wallet]
        )

        XCTAssertEqual(presentation.inputTarget, .aaPeople)
    }

    func testAAPeopleInputRequiresAnIntegerOfAtLeastTwo() {
        let wallet = makeWallet(name: "银行卡")
        let form = TransactionFormState(kind: .expense)
        var presentation = preparedPresentation(
            kind: .aa,
            form: form,
            wallets: [wallet]
        )

        presentation.draft?.aaPeopleText = "1"
        XCTAssertFalse(presentation.synchronizePendingInput())

        presentation.draft?.aaPeopleText = "12"
        XCTAssertTrue(presentation.synchronizePendingInput())
        XCTAssertEqual(presentation.draft?.aaPeople, 12)
    }

    func testAAKeypadInputChangesPeopleWithoutChangingTheMainAmount() {
        let wallet = makeWallet(name: "银行卡")
        var form = TransactionFormState(kind: .expense)
        form.amountText = "88"
        var presentation = preparedPresentation(
            kind: .aa,
            form: form,
            wallets: [wallet]
        )

        presentation.draft?.aaPeopleText = "5"
        XCTAssertTrue(presentation.synchronizePendingInput())
        presentation.beginClosing(intent: .commit)
        presentation.finishClosing(state: &form)

        XCTAssertEqual(form.amountText, "88")
        XCTAssertEqual(form.aaSplitDraft?.otherPeopleCount, 4)
    }

    func testAccountSelectionAppliesOnCommit() {
        let first = makeWallet(name: "第一张卡")
        let second = makeWallet(name: "第二张卡")
        var form = TransactionFormState(kind: .expense)
        form.sourceWalletID = first.id
        var presentation = preparedPresentation(
            kind: .account,
            form: form,
            wallets: [first, second]
        )

        presentation.draft?.selectedWalletID = second.id
        presentation.beginClosing(intent: .commit)
        presentation.finishClosing(state: &form)

        XCTAssertEqual(form.sourceWalletID, second.id)
    }

    func testTransferDiscountDefaultsToDestinationAndCommitsWallet() {
        let source = makeWallet(name: "转出卡")
        let destination = makeWallet(name: "转入卡")
        var form = TransactionFormState(kind: .transfer)
        form.sourceWalletID = source.id
        form.destinationWalletID = destination.id
        var presentation = preparedPresentation(
            kind: .discount,
            form: form,
            wallets: [source, destination]
        )

        XCTAssertEqual(presentation.draft?.discountWalletID, destination.id)
        presentation.draft?.discountAmountText = "8.5"
        XCTAssertTrue(presentation.synchronizePendingInput())
        presentation.beginClosing(intent: .commit)
        presentation.finishClosing(state: &form)

        XCTAssertEqual(form.discountAmountText, "8.5")
        XCTAssertEqual(form.discountWalletID, destination.id)
    }

    func testTransferFeeDefaultsToSourceAndCommitsWallet() {
        let source = makeWallet(name: "转出卡")
        let destination = makeWallet(name: "转入卡")
        var form = TransactionFormState(kind: .transfer)
        form.sourceWalletID = source.id
        form.destinationWalletID = destination.id
        form.amountText = "100"
        var presentation = preparedPresentation(
            kind: .fee,
            form: form,
            wallets: [source, destination]
        )

        XCTAssertEqual(presentation.draft?.feeWalletID, source.id)
        presentation.draft?.feeInputMode = .fixedAmount
        presentation.draft?.feeInputText = "3"
        XCTAssertTrue(presentation.synchronizePendingInput())
        presentation.beginClosing(intent: .commit)
        presentation.finishClosing(state: &form)

        XCTAssertTrue(form.includesFee)
        XCTAssertEqual(form.feeText, "3")
        XCTAssertEqual(form.feeWalletID, source.id)
    }

    func testEditingPreservesExplicitCrossCurrencyFeeWallet() {
        let source = makeWallet(name: "转出卡")
        let destination = makeWallet(name: "转入卡")
        let feeWallet = makeWallet(name: "美元现金", currency: .USD)
        var form = TransactionFormState(kind: .transfer)
        form.sourceWalletID = source.id
        form.destinationWalletID = destination.id
        form.feeWalletID = feeWallet.id

        let presentation = preparedPresentation(
            kind: .fee,
            form: form,
            wallets: [source, destination, feeWallet]
        )

        XCTAssertEqual(presentation.draft?.feeWalletID, feeWallet.id)
        XCTAssertEqual(presentation.draft?.feeCurrencyCode, SupportedCurrency.USD.rawValue)
    }

    func testTransferDiscountWithoutWalletCannotCommit() {
        let source = makeWallet(name: "转出卡")
        let destination = makeWallet(name: "转入卡")
        var form = TransactionFormState(kind: .transfer)
        form.sourceWalletID = source.id
        form.destinationWalletID = destination.id
        var presentation = preparedPresentation(
            kind: .discount,
            form: form,
            wallets: [source, destination]
        )

        presentation.draft?.discountAmountText = "2"
        presentation.draft?.discountWalletID = nil

        XCTAssertFalse(presentation.synchronizePendingInput())
    }

    func testInputTargetTracksActiveSplitPaymentPart() {
        let first = makeWallet(name: "主卡")
        let second = makeWallet(name: "备用卡")
        var form = TransactionFormState(kind: .expense)
        form.sourceWalletID = first.id
        var presentation = preparedPresentation(
            kind: .splitPayment,
            form: form,
            wallets: [first, second]
        )

        XCTAssertEqual(presentation.inputTarget, .splitPayment(index: 0))

        presentation.selectPaymentPart(1)

        XCTAssertEqual(presentation.inputTarget, .splitPayment(index: 1))
    }

    func testGenieProgressUsesCollapsedToExpandedDirection() {
        let wallet = makeWallet(name: "银行卡")
        let form = TransactionFormState(kind: .expense)
        var presentation = EntryContextPresentationState()
        let visual = EntryContextTagVisual(
            title: "AA",
            isSelected: false
        )

        presentation.prepare(
            kind: .aa,
            sourceFrame: CGRect(x: 20, y: 500, width: 60, height: 27),
            sourceTagVisual: visual,
            state: form,
            wallets: [wallet]
        )

        XCTAssertEqual(presentation.progress, 1)
        XCTAssertEqual(presentation.backdropProgress, 0)
        XCTAssertEqual(presentation.sourceTagVisual, visual)

        presentation.beginOpening(
            targetFrame: CGRect(x: 18, y: 80, width: 360, height: 180)
        )
        presentation.finishOpening()

        XCTAssertEqual(presentation.progress, 0)
        XCTAssertEqual(presentation.backdropProgress, 1)

        presentation.beginClosing(intent: .cancel)
        presentation.progress = 1

        XCTAssertEqual(presentation.backdropProgress, 0)
    }

    private func preparedPresentation(
        kind: EntryContextOverlayKind,
        form: TransactionFormState,
        wallets: [CurrencyWallet]
    ) -> EntryContextPresentationState {
        var presentation = EntryContextPresentationState()
        presentation.prepare(
            kind: kind,
            sourceFrame: CGRect(x: 20, y: 500, width: 80, height: 27),
            sourceTagVisual: EntryContextTagVisual(
                title: kind == .aa ? "AA" : kind.rawValue,
                isSelected: false
            ),
            state: form,
            wallets: wallets
        )
        presentation.beginOpening(
            targetFrame: CGRect(x: 18, y: 80, width: 360, height: 180)
        )
        presentation.finishOpening()
        return presentation
    }

    private func makeWallet(
        name: String,
        currency: SupportedCurrency = .CNY
    ) -> CurrencyWallet {
        CurrencyWallet(
            currency: currency,
            account: Account(name: name, type: .bankCard)
        )
    }
}
