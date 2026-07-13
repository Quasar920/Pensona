import XCTest
@testable import MultiCurrencyLedger

final class TransactionImpactCalculatorTests: XCTestCase {
    func testExpenseIncomeAndAdjustmentProduceSingleWalletDelta() throws {
        let wallet = makeWallet(currency: .CNY)
        let calculator = TransactionImpactCalculator()

        let expense = TransactionDraft(type: .expense, amount: 80, sourceWallet: wallet)
        XCTAssertEqual(try calculator.deltas(for: expense), [WalletDelta(wallet: wallet, amount: -80)])

        let income = TransactionDraft(type: .income, amount: 500, sourceWallet: wallet)
        XCTAssertEqual(try calculator.deltas(for: income), [WalletDelta(wallet: wallet, amount: 500)])

        var adjustment = TransactionDraft(type: .adjustment, amount: 25, sourceWallet: wallet)
        adjustment.adjustmentDirection = .decrease
        adjustment.adjustmentReason = "手动校准"
        XCTAssertEqual(try calculator.deltas(for: adjustment), [WalletDelta(wallet: wallet, amount: -25)])
    }

    func testTransferAggregatesPrincipalAndFeeForTheSameSourceWallet() throws {
        let source = makeWallet(currency: .CNY)
        let destination = makeWallet(currency: .CNY)
        var draft = TransactionDraft(type: .transfer, amount: 100, sourceWallet: source)
        draft.destinationWallet = destination
        draft.feeAmount = 5
        draft.feeWallet = source

        XCTAssertEqual(
            try TransactionImpactCalculator().deltas(for: draft),
            [
                WalletDelta(wallet: source, amount: -105),
                WalletDelta(wallet: destination, amount: 100)
            ]
        )
    }

    func testExchangeUsesDestinationAmountAndIndependentFeeWallet() throws {
        let cny = makeWallet(currency: .CNY)
        let usd = makeWallet(currency: .USD)
        let fee = makeWallet(currency: .HKD)
        var draft = TransactionDraft(type: .exchange, amount: 700, sourceWallet: cny)
        draft.destinationWallet = usd
        draft.destinationAmount = 100
        draft.feeAmount = 8
        draft.feeWallet = fee

        XCTAssertEqual(
            try TransactionImpactCalculator().deltas(for: draft),
            [
                WalletDelta(wallet: cny, amount: -700),
                WalletDelta(wallet: usd, amount: 100),
                WalletDelta(wallet: fee, amount: -8)
            ]
        )
    }

    func testRejectsInvalidCategoryTransferAndExchangeRules() {
        let cny = makeWallet(currency: .CNY)
        let anotherCNY = makeWallet(currency: .CNY)
        let incomeCategory = LedgerCategory(
            name: "工资", type: .income, symbolName: "banknote", sortOrder: 0
        )
        let calculator = TransactionImpactCalculator()

        var expense = TransactionDraft(type: .expense, amount: 10, sourceWallet: cny)
        expense.category = incomeCategory
        XCTAssertThrowsError(try calculator.deltas(for: expense)) {
            XCTAssertEqual($0 as? LedgerError, .categoryMismatch)
        }

        var transfer = TransactionDraft(type: .transfer, amount: 10, sourceWallet: cny)
        transfer.destinationWallet = cny
        XCTAssertThrowsError(try calculator.deltas(for: transfer)) {
            XCTAssertEqual($0 as? LedgerError, .sameWallet)
        }

        var exchange = TransactionDraft(type: .exchange, amount: 10, sourceWallet: cny)
        exchange.destinationWallet = anotherCNY
        exchange.destinationAmount = 10
        XCTAssertThrowsError(try calculator.deltas(for: exchange)) {
            XCTAssertEqual($0 as? LedgerError, .sameCurrencyExchange)
        }
    }

    private func makeWallet(currency: SupportedCurrency) -> CurrencyWallet {
        let account = Account(name: UUID().uuidString, type: .bankCard)
        return CurrencyWallet(currency: currency, account: account)
    }
}
