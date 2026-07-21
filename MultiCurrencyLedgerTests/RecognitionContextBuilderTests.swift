import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RecognitionContextBuilderTests: XCTestCase {
    func testBuildsEnabledWalletAndExactCategoryOptionsInDeterministicOrder() {
        let book = LedgerBook(name: "日常账本")
        let higherIDAccount = Account(name: "招商银行 1234", type: .bankCard, note: "工资卡", book: book)
        let higherIDWallet = CurrencyWallet(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            currency: .CNY,
            account: higherIDAccount
        )
        let disabledUSD = CurrencyWallet(currency: .USD, isEnabled: false, account: higherIDAccount)
        higherIDAccount.wallets = [higherIDWallet, disabledUSD]

        let lowerIDAccount = Account(name: "招商银行 1234", type: .bankCard, note: "日常卡", book: book)
        let lowerIDWallet = CurrencyWallet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currency: .CNY,
            account: lowerIDAccount
        )
        lowerIDAccount.wallets = [lowerIDWallet]
        book.accounts = [higherIDAccount, lowerIDAccount]
        let categories = [
            LedgerCategory(name: "工资", type: .income, symbolName: "banknote", sortOrder: 0),
            LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 1),
            LedgerCategory(name: "交通", type: .expense, symbolName: "bus", sortOrder: 0)
        ]

        let context = RecognitionContextBuilder().makeContext(
            book: book,
            accounts: [higherIDAccount, lowerIDAccount],
            categories: categories
        )

        XCTAssertEqual(
            context,
            RecognitionRequestContext(
                bookID: book.id,
                bookName: "日常账本",
                accounts: [
                    RecognitionAccountOption(
                        walletID: lowerIDWallet.id,
                        accountName: "招商银行 1234",
                        accountNote: "日常卡",
                        currencyCode: "CNY"
                    ),
                    RecognitionAccountOption(
                        walletID: higherIDWallet.id,
                        accountName: "招商银行 1234",
                        accountNote: "工资卡",
                        currencyCode: "CNY"
                    )
                ],
                categories: [
                    RecognitionCategoryOption(name: "交通", type: .expense),
                    RecognitionCategoryOption(name: "餐饮", type: .expense),
                    RecognitionCategoryOption(name: "工资", type: .income)
                ]
            )
        )
    }
}
