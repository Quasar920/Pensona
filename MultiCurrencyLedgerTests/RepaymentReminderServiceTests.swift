import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RepaymentReminderServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self,
            LedgerTransaction.self, RepaymentReminder.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testLifecycleCreateUpdateCompleteReopenAndDelete() throws {
        let first = makeAccount(name: "信用卡", currency: .CNY)
        let second = makeAccount(name: "美元卡", currency: .USD)
        let service = RepaymentReminderService(context: context)

        let reminder = try service.create(
            accountID: first.id,
            currencyCode: "cny",
            outstandingAmount: 1_200,
            dueDate: date(2026, 7, 25)
        )
        XCTAssertEqual(reminder.currencyCode, "CNY")
        XCTAssertFalse(reminder.isCompleted)

        try service.update(
            reminder,
            accountID: second.id,
            currencyCode: "USD",
            outstandingAmount: 88,
            dueDate: date(2026, 8, 8)
        )
        XCTAssertEqual(reminder.accountID, second.id)
        XCTAssertEqual(reminder.outstandingAmount, 88)

        try service.setCompleted(true, reminder: reminder)
        XCTAssertTrue(reminder.isCompleted)
        XCTAssertNotNil(reminder.completedAt)

        try service.setCompleted(false, reminder: reminder)
        XCTAssertFalse(reminder.isCompleted)
        XCTAssertNil(reminder.completedAt)

        try service.delete(reminder)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepaymentReminder>()), 0)
    }

    func testCompletionOnlyChangesReminderState() throws {
        let account = makeAccount(name: "花呗", currency: .CNY)
        let service = RepaymentReminderService(context: context)
        let reminder = try service.create(
            accountID: account.id,
            currencyCode: "CNY",
            outstandingAmount: 300,
            dueDate: .now
        )

        try service.setCompleted(true, reminder: reminder)

        XCTAssertTrue(reminder.isCompleted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepaymentReminder>()), 1)
    }

    func testReminderIsIndependentOfBookAndValidatesAccountCurrency() throws {
        let firstBook = LedgerBook(name: "日常")
        let secondBook = LedgerBook(name: "旅行")
        context.insert(firstBook)
        context.insert(secondBook)
        let account = Account(name: "信用卡", type: .creditCard, book: firstBook)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        context.insert(account)
        context.insert(wallet)
        let service = RepaymentReminderService(context: context)

        _ = try service.create(
            accountID: account.id,
            currencyCode: "CNY",
            outstandingAmount: 500,
            dueDate: .now
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepaymentReminder>()), 1)
        XCTAssertThrowsError(try service.create(
            accountID: account.id,
            currencyCode: "USD",
            outstandingAmount: 10,
            dueDate: .now
        )) { error in
            XCTAssertEqual(error as? RepaymentReminderError, .unsupportedCurrency)
        }
        XCTAssertNotNil(secondBook.id)
    }

    private func makeAccount(name: String, currency: SupportedCurrency) -> Account {
        let book = LedgerBook(name: "\(name)账本")
        let account = Account(name: name, type: .creditCard, book: book)
        let wallet = CurrencyWallet(currency: currency, account: account)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        return account
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
