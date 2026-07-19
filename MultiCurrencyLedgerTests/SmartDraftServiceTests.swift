import XCTest
@testable import MultiCurrencyLedger

final class SmartDraftServiceTests: XCTestCase {
    func testChineseExpenseTextBuildsConfirmableDraftWithoutTreatingDateAsAmount() throws {
        let account = Account(name: "支付宝", type: .eWallet)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        let result = try SmartDraftService().parse(
            "2026-07-12 用支付宝花 28.5 元吃午饭 餐饮",
            wallets: [wallet],
            categories: [category],
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.draft.type, .expense)
        XCTAssertEqual(result.draft.amount, Decimal(string: "28.5"))
        XCTAssertEqual(result.draft.sourceWallet?.id, wallet.id)
        XCTAssertEqual(result.draft.category?.id, category.id)
    }

    func testTransferRequiresAndResolvesTwoNamedAccounts() throws {
        let cash = Account(name: "现金", type: .cash)
        let bank = Account(name: "银行卡", type: .bankCard)
        let source = CurrencyWallet(currency: .CNY, balance: 500, account: cash)
        let destination = CurrencyWallet(currency: .CNY, account: bank)

        let result = try SmartDraftService().parse(
            "从现金转账 100 到银行卡",
            wallets: [source, destination],
            categories: []
        )

        XCTAssertEqual(result.draft.type, .transfer)
        XCTAssertEqual(result.draft.sourceWallet?.id, source.id)
        XCTAssertEqual(result.draft.destinationWallet?.id, destination.id)
    }

    func testMissingAmountIsRejectedBeforeConfirmation() {
        XCTAssertThrowsError(try SmartDraftService().parse(
            "昨天用现金吃午饭",
            wallets: [],
            categories: []
        )) { error in
            XCTAssertEqual(error as? SmartDraftError, .missingAmount)
        }
    }
}
