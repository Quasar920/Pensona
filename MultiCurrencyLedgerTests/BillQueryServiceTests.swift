import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class BillQueryServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionRelation.self, ExchangeRate.self,
            MonthlyBudget.self, AASplit.self, AASettlement.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testFetchDescriptorLimitsRowsToBookAndHalfOpenMonth() throws {
        let firstBook = LedgerBook(name: "日常")
        let secondBook = LedgerBook(name: "旅行")
        let included = transaction(bookID: firstBook.id, amount: 10, date: date("2026-07-31T23:59:59Z"))
        let atNextMonth = transaction(bookID: firstBook.id, amount: 20, date: date("2026-08-01T00:00:00Z"))
        let wrongBook = transaction(bookID: secondBook.id, amount: 30, date: date("2026-07-20T12:00:00Z"))
        [firstBook, secondBook].forEach(context.insert)
        [included, atNextMonth, wrongBook].forEach(context.insert)
        try context.save()

        let snapshot = try service.load(
            bookID: firstBook.id,
            month: date("2026-07-15T00:00:00Z"),
            baseCurrencyCode: "CNY"
        )

        XCTAssertEqual(snapshot.transactions.map(\.id), [included.id])
        XCTAssertEqual(snapshot.summary.expense, 10)
        XCTAssertEqual(snapshot.monthInterval.end, date("2026-08-01T00:00:00Z"))
    }

    func testGroupsSearchAndSummaryStayWithinFetchedMonth() throws {
        let book = LedgerBook(name: "日常")
        let coffee = transaction(
            bookID: book.id,
            amount: 28,
            date: date("2026-07-10T08:00:00Z"),
            note: "咖啡"
        )
        let lunch = transaction(
            bookID: book.id,
            amount: 42,
            date: date("2026-07-10T12:00:00Z"),
            note: "午餐"
        )
        let income = LedgerTransaction(
            type: .income,
            bookID: book.id,
            amount: 500,
            currencyCode: "CNY",
            date: date("2026-07-11T09:00:00Z"),
            note: "工资"
        )
        context.insert(book)
        [coffee, lunch, income].forEach(context.insert)
        try context.save()

        let snapshot = try service.load(
            bookID: book.id,
            month: date("2026-07-01T00:00:00Z"),
            baseCurrencyCode: "CNY",
            keyword: "咖啡"
        )

        XCTAssertEqual(snapshot.transactions.map(\.id), [coffee.id])
        XCTAssertEqual(snapshot.dayGroups.count, 1)
        XCTAssertEqual(snapshot.dayGroups.first?.income, 0)
        XCTAssertEqual(snapshot.dayGroups.first?.expense, 70)
        XCTAssertEqual(snapshot.summary.expense, 70)
        XCTAssertEqual(snapshot.summary.income, 500)
    }

    func testLargeHistoricalStoreStillReturnsOnlyTheSelectedMonth() throws {
        let book = LedgerBook(name: "长期账本")
        context.insert(book)
        for index in 0..<300 {
            context.insert(transaction(
                bookID: book.id,
                amount: Decimal(index + 1),
                date: date("2025-01-15T12:00:00Z")
            ))
        }
        let current = transaction(
            bookID: book.id,
            amount: 88,
            date: date("2026-07-18T12:00:00Z")
        )
        context.insert(current)
        try context.save()

        let snapshot = try service.load(
            bookID: book.id,
            month: date("2026-07-01T00:00:00Z"),
            baseCurrencyCode: "CNY"
        )

        XCTAssertEqual(snapshot.transactions.map(\.id), [current.id])
        XCTAssertEqual(snapshot.dayGroups.first?.transactions.count, 1)
    }

    func testBillPageStateOnlyMovesToAdjacentMonthsAndClearsSearch() {
        var state = BillPageState(selectedMonth: date("2026-07-18T00:00:00Z"))
        state.searchText = "午餐"
        state.isSearchExpanded = true

        state.changeMonth(by: -1, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: state.selectedMonth), 6)
        state.collapseSearch()
        XCTAssertEqual(state.searchText, "")
        XCTAssertFalse(state.isSearchExpanded)
    }

    private var service: BillQueryService {
        BillQueryService(context: context, calendar: calendar)
    }

    private func transaction(
        bookID: UUID,
        amount: Decimal,
        date: Date,
        note: String? = nil
    ) -> LedgerTransaction {
        LedgerTransaction(
            type: .expense,
            bookID: bookID,
            amount: amount,
            currencyCode: "CNY",
            date: date,
            note: note
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
