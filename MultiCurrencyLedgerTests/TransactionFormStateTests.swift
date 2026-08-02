import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class TransactionFormStateTests: XCTestCase {
    func testExchangeDraftUsesIndependentFeeWalletAndCanonicalFields() throws {
        let sourceAccount = Account(name: "港币", type: .bankCard)
        let destinationAccount = Account(name: "美元", type: .bankCard)
        let feeAccount = Account(name: "现金", type: .cash)
        let source = CurrencyWallet(currency: .HKD, balance: 1_000, account: sourceAccount)
        let destination = CurrencyWallet(currency: .USD, balance: 0, account: destinationAccount)
        let fee = CurrencyWallet(currency: .CNY, balance: 100, account: feeAccount)

        var state = TransactionFormState(kind: .exchange)
        state.amountText = "780"
        state.destinationAmountText = "100"
        state.sourceWalletID = source.id
        state.destinationWalletID = destination.id
        state.includesFee = true
        state.feeText = "2"
        state.feeWalletID = fee.id
        state.merchantOrCounterparty = "  银行柜台  "

        let draft = try state.makeDraft(wallets: [source, destination, fee], categories: [])

        XCTAssertEqual(draft.amount, 780)
        XCTAssertEqual(draft.destinationAmount, 100)
        XCTAssertEqual(draft.feeAmount, 2)
        XCTAssertEqual(draft.feeWallet?.id, fee.id)
        XCTAssertEqual(draft.merchantOrCounterparty, "银行柜台")
    }

    func testContinuousEntryPreservesSelectionsButClearsPerEntryContent() {
        var state = TransactionFormState(kind: .expense)
        let originalDate = state.date
        let walletID = UUID()
        let categoryID = UUID()
        state.sourceWalletID = walletID
        state.categoryID = categoryID
        state.amountText = "88"
        state.note = "午餐"
        state.merchantOrCounterparty = "小店"
        state.includesFee = true
        state.feeText = "1"

        state.resetForContinuousEntry(now: Date(timeIntervalSince1970: 123))

        XCTAssertEqual(state.sourceWalletID, walletID)
        XCTAssertNil(state.categoryID)
        XCTAssertEqual(state.amountText, "")
        XCTAssertEqual(state.note, "")
        XCTAssertEqual(state.merchantOrCounterparty, "")
        XCTAssertFalse(state.includesFee)
        XCTAssertEqual(state.date, originalDate)
    }

    func testCopyRemovesRecognitionMetadataAndUsesNewDate() throws {
        let account = Account(name: "卡", type: .bankCard)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let imported = TransactionDraft(
            type: .expense,
            amount: 20,
            sourceWallet: wallet,
            originalAmount: 25,
            discountAmount: 5,
            recognitionImportID: UUID()
        )
        var state = TransactionFormState(draft: imported)

        state.removeImportedMetadataForCopy(now: Date(timeIntervalSince1970: 456))
        let copy = try state.makeDraft(wallets: [wallet], categories: [])

        XCTAssertNil(copy.originalAmount)
        XCTAssertNil(copy.discountAmount)
        XCTAssertNil(copy.recognitionImportID)
        XCTAssertEqual(copy.date, Date(timeIntervalSince1970: 456))
    }

    func testInstantForeignExpenseKeepsOriginalInputButPostsSettlementAmount() throws {
        let card = Account(
            name: "信用卡",
            type: .creditCard,
            defaultForeignCurrencySettlementMode: .instant,
            defaultSettlementCurrencyCode: "CNY"
        )
        let cny = CurrencyWallet(currency: .CNY, account: card)
        let usd = CurrencyWallet(currency: .USD, account: card)
        var state = TransactionFormState(kind: .expense)
        state.sourceWalletID = usd.id
        state.amountText = "100"
        state.foreignOriginalCurrencyCode = "USD"
        state.foreignSettlementMode = .instant
        state.settledAmountText = "710"

        let draft = try state.makeDraft(wallets: [cny, usd], categories: [])

        XCTAssertEqual(draft.amount, 710)
        XCTAssertEqual(draft.sourceWallet?.id, cny.id)
        XCTAssertEqual(draft.foreignOriginalAmount, 100)
        XCTAssertEqual(draft.foreignOriginalCurrencyCode, "USD")
        XCTAssertEqual(draft.settlementCurrencyCode, "CNY")
        XCTAssertEqual(draft.settledAmount, 710)
    }

    func testCreditCardDestinationAutomaticallyCreatesRepaymentWithChosenAdjustmentWallets() throws {
        let bank = Account(name: "储蓄卡", type: .bankCard)
        let card = Account(name: "信用卡", type: .creditCard)
        let cny = CurrencyWallet(currency: .CNY, balance: 1_000, account: bank)
        let usd = CurrencyWallet(currency: .USD, balance: -100, account: card)
        var state = TransactionFormState(kind: .transfer)
        state.sourceWalletID = cny.id
        state.destinationWalletID = usd.id
        state.amountText = "350"
        state.destinationAmountText = "50"
        state.includesFee = true
        state.feeText = "3"
        state.feeWalletID = cny.id
        state.discountAmountText = "2"
        state.discountWalletID = usd.id

        let draft = try state.makeDraft(wallets: [cny, usd], categories: [])

        XCTAssertEqual(draft.transferPurpose, .creditCardRepayment)
        XCTAssertEqual(draft.amount, 350)
        XCTAssertEqual(draft.destinationAmount, 50)
        XCTAssertEqual(draft.feeWallet?.id, cny.id)
        XCTAssertEqual(draft.discountWallet?.id, usd.id)
    }
}
