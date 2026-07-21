import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class TransactionBookScopeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dailyBook: LedgerBook!
    private var travelBook: LedgerBook!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: LedgerSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        dailyBook = LedgerBook(name: "日常")
        travelBook = LedgerBook(name: "旅行")
        context.insert(dailyBook)
        context.insert(travelBook)
        try context.save()
    }

    func testNewAccountIsGlobalAndCanWriteTransactionsIntoEitherBook() throws {
        let account = try AccountService(context: context).createAccount(
            name: "全局现金", type: .cash, note: nil
        )
        XCTAssertNil(account.book)
        let wallet = try AccountService(context: context).addWallet(
            currency: .CNY, initialBalance: 0, to: account, bookID: dailyBook.id
        )
        let service = LedgerService(context: context)
        let daily = try service.createExpense(
            bookID: dailyBook.id, amount: 10, wallet: wallet, category: nil, date: .now, note: nil
        )
        let travel = try service.createExpense(
            bookID: travelBook.id, amount: 20, wallet: wallet, category: nil, date: .now, note: nil
        )

        XCTAssertEqual(daily.bookID, dailyBook.id)
        XCTAssertEqual(travel.bookID, travelBook.id)
        XCTAssertNil(account.book)
    }

    func testScopeAndQueryReadOnlyTransactionBookID() {
        let legacyAccount = Account(name: "旧账户", type: .cash, book: dailyBook)
        let travelTransaction = LedgerTransaction(
            type: .expense,
            bookID: travelBook.id,
            sourceAccount: legacyAccount
        )
        let dailyTransaction = LedgerTransaction(
            type: .expense,
            bookID: dailyBook.id,
            sourceAccount: legacyAccount
        )
        let scope = LedgerScope(
            bookID: travelBook.id,
            selectedMonth: .now,
            baseCurrencyCode: "CNY"
        )
        let query = TransactionQueryState(bookID: travelBook.id)

        XCTAssertTrue(scope.transactionBelongsToBook(travelTransaction))
        XCTAssertFalse(scope.transactionBelongsToBook(dailyTransaction))
        XCTAssertEqual(query.applying(to: [dailyTransaction, travelTransaction]).map(\.id), [travelTransaction.id])
    }

    func testEditingPreservesBookUntilExplicitMove() throws {
        let account = Account(name: "现金", type: .cash)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        context.insert(account)
        context.insert(wallet)
        let service = LedgerService(context: context)
        let transaction = try service.create(
            TransactionDraft(type: .expense, amount: 10, sourceWallet: wallet),
            bookID: dailyBook.id
        )

        try service.replaceTransaction(
            transaction,
            with: TransactionDraft(type: .expense, amount: 25, sourceWallet: wallet)
        )
        XCTAssertEqual(transaction.bookID, dailyBook.id)

        try service.moveTransaction(transaction, toBookID: travelBook.id)
        XCTAssertEqual(transaction.bookID, travelBook.id)
        XCTAssertEqual(wallet.balance, 75)
    }
}
