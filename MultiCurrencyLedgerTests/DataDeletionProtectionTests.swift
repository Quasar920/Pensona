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

    func testDeletingRefundAlsoDeletesItsGeneratedRefundIncome() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let refundIncome = LedgerCategory(
            name: "退款收入",
            type: .income,
            symbolName: "arrow.uturn.backward.circle",
            sortOrder: 0,
            isSystem: true,
            systemLocalizationKey: "category.income.other.refund-income"
        )
        context.insert(book); context.insert(account); context.insert(wallet); context.insert(refundIncome)
        let original = try LedgerService(context: context).createExpense(
            bookID: book.id, amount: 10, wallet: wallet, category: nil, date: .now, note: nil
        )
        let refund = try TransactionRelationService(context: context).record(
            kind: .refund, original: original, amount: 12, wallet: wallet
        )

        try LedgerService(context: context).deleteTransaction(refund)

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.id, original.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TransactionRelation>()), 0)
        XCTAssertEqual(wallet.balance, 90)
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
