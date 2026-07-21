import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class DataDeletionProtectionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(LedgerSchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testReferencedAccountCannotBeDeleted() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        context.insert(book); context.insert(account); context.insert(wallet)
        let transaction = try LedgerService(context: context).createExpense(
            bookID: book.id,
            amount: 20,
            wallet: wallet,
            category: nil,
            date: .now,
            note: nil
        )

        XCTAssertThrowsError(
            try AccountService(context: context).deleteAccount(account, transactions: [transaction])
        ) { error in
            XCTAssertEqual(error as? LedgerError, .accountInUse)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Account>()), 1)
        XCTAssertEqual(wallet.balance, 80)
    }

    func testOnlyOrReferencedBookCannotBeDeleted() throws {
        let book = LedgerBook(name: "日常")
        context.insert(book)
        try context.save()
        let service = LedgerBookService(context: context)

        XCTAssertThrowsError(try service.delete(book)) { error in
            XCTAssertEqual(error as? LedgerError, .bookInUse)
        }

        let second = LedgerBook(name: "旅行")
        context.insert(second)
        context.insert(MonthlyBudget(
            scopeKey: "deletion-protection-\(book.id.uuidString.lowercased())",
            bookID: book.id,
            monthStart: .now,
            currencyCode: "CNY",
            amount: 1_000
        ))
        try context.save()

        XCTAssertThrowsError(try service.delete(book)) { error in
            XCTAssertEqual(error as? LedgerError, .bookInUse)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerBook>()), 2)
    }
}
