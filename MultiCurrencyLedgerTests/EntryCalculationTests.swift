import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class EntryCalculationTests: XCTestCase {
    func testFourOperatorsUseDecimalAndRespectCurrencyPrecision() {
        XCTAssertEqual(calculate("10", .add, "3", scale: 2), "13")
        XCTAssertEqual(calculate("10", .subtract, "3", scale: 2), "7")
        XCTAssertEqual(calculate("10", .multiply, "3", scale: 2), "30")
        XCTAssertEqual(calculate("10", .divide, "3", scale: 2), "3.33")
        XCTAssertEqual(calculate("10", .divide, "3", scale: 0), "3")
    }

    func testDivisionByZeroKeepsTheLastValidDisplay() {
        var state = EntryCalculationState()
        var display = "12"
        state.begin(.divide, displayText: display)
        state.append("0", displayText: &display, fractionDigits: 2)
        XCTAssertEqual(display, "12")
        XCTAssertEqual(state.expression, "12 ÷ 0")
    }

    func testExchangeLinkUpdatesTheOtherValueWithoutDoubleConversion() {
        let destination = EntryExchangeCalculation.update(
            sourceText: "780",
            destinationText: "",
            rateText: "0.12820513",
            driver: .sourceAmount,
            sourceFractionDigits: 2,
            destinationFractionDigits: 2
        )
        XCTAssertEqual(destination.destination, "100")

        let rate = EntryExchangeCalculation.update(
            sourceText: "780",
            destinationText: "100",
            rateText: destination.rate,
            driver: .destinationAmount,
            sourceFractionDigits: 2,
            destinationFractionDigits: 2
        )
        XCTAssertEqual(rate.rate, "0.12820513")
    }

    func testAdjustmentFinalBalanceConvertsToCanonicalDirectionAndDelta() throws {
        let account = Account(name: "现金", type: .cash)
        let wallet = CurrencyWallet(currency: .CNY, balance: 125, account: account)
        var state = TransactionFormState(kind: .adjustment)
        state.sourceWalletID = wallet.id
        state.adjustmentInputMode = .finalBalance
        state.amountText = "100"

        let draft = try state.makeDraft(wallets: [wallet], categories: [])
        XCTAssertEqual(draft.amount, 25)
        XCTAssertEqual(draft.adjustmentDirection, .decrease)
    }

    func testExpenseDraftPersistsPendingReimbursement() throws {
        let account = Account(name: "卡", type: .bankCard)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let category = LedgerCategory(
            name: "餐饮",
            type: .expense,
            symbolName: "fork.knife",
            sortOrder: 0,
            bookID: UUID()
        )
        var state = TransactionFormState(kind: .expense)
        state.sourceWalletID = wallet.id
        state.categoryID = category.id
        state.amountText = "20"
        state.reimbursementStatus = .pending

        let draft = try state.makeDraft(wallets: [wallet], categories: [category])
        XCTAssertEqual(draft.reimbursementStatus, .pending)
    }

    private func calculate(
        _ left: String,
        _ operation: EntryCalculationOperator,
        _ right: String,
        scale: Int
    ) -> String {
        var state = EntryCalculationState()
        var display = left
        state.begin(operation, displayText: display)
        for character in right { state.append(String(character), displayText: &display, fractionDigits: scale) }
        return display
    }
}
