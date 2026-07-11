import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RecognitionContextBuilderTests: XCTestCase {
    func testBuildsEnabledWalletAndExactCategoryOptions() throws {
        let book = LedgerBook(name: "日常账本")
        let account = Account(name: "招商银行 1234", type: .bankCard, note: "工资卡", book: book)
        let cny = CurrencyWallet(currency: .CNY, account: account)
        let disabledUSD = CurrencyWallet(currency: .USD, isEnabled: false, account: account)
        account.wallets = [cny, disabledUSD]
        book.accounts = [account]
        let categories = [
            LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0),
            LedgerCategory(name: "工资", type: .income, symbolName: "banknote", sortOrder: 0)
        ]

        let context = RecognitionContextBuilder().makeContext(book: book, categories: categories)

        XCTAssertEqual(context.bookID, book.id)
        XCTAssertEqual(context.accounts.map(\.walletID), [cny.id])
        XCTAssertEqual(context.accounts.first?.accountName, "招商银行 1234")
        XCTAssertEqual(context.categories.map(\.name), ["餐饮", "工资"])
    }
}
