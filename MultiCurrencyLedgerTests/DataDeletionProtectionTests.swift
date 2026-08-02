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

    func testEmptyBookCanBeDeletedEvenWhenItIsTheOnlyBook() throws {
        let book = LedgerBook(name: "日常")
        context.insert(book)
        try context.save()
        let service = LedgerBookService(context: context)

        XCTAssertNoThrow(try service.delete(book))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerBook>()), 0)
    }

    func testBookWithContentCanArchiveButCannotDeleteOrRecordNewTransactions() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        try context.save()
        let service = LedgerBookService(context: context)

        XCTAssertThrowsError(try service.delete(book)) { error in
            XCTAssertEqual(error as? LedgerError, .bookInUse)
        }
        XCTAssertNoThrow(try service.archive(book))
        XCTAssertTrue(book.isArchived)
        XCTAssertNotNil(book.archivedAt)
        XCTAssertThrowsError(
            try LedgerService(context: context).createExpense(
                bookID: book.id,
                amount: 20,
                wallet: wallet,
                category: nil,
                date: .now,
                note: nil
            )
        ) { error in
            XCTAssertEqual(error as? LedgerError, .bookArchived)
        }
        XCTAssertNoThrow(try service.restore(book))
        XCTAssertFalse(book.isArchived)
        XCTAssertNil(book.archivedAt)
    }
}
