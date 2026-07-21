import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class StatisticsDashboardServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, ExchangeRate.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testLoadFetchesOnlyRequestedBookAndHalfOpenRange() async throws {
        let first = makeFixture(bookName: "日常")
        let second = makeFixture(bookName: "旅行")
        insertExpense(10, date: date(2026, 7, 1), fixture: first)
        insertExpense(20, date: date(2026, 8, 1), fixture: first)
        insertExpense(30, date: date(2026, 7, 2), fixture: second)
        try context.save()
        let service = StatisticsDashboardService(context: context, calendar: calendar)

        let result = try await service.load(
            bookID: first.book.id,
            section: .categories,
            interval: DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1)),
            baseCurrencyCode: "CNY"
        )

        XCTAssertEqual(result.transactionCount, 1)
        XCTAssertEqual(result.expense, 10)
        XCTAssertEqual(result.buckets.map(\.title), ["餐饮"])
    }

    func testEachSectionProducesOnlyItsRequestedGrouping() async throws {
        let fixture = makeFixture(bookName: "日常")
        insertExpense(60, date: date(2026, 7, 10), fixture: fixture)
        try context.save()
        let service = StatisticsDashboardService(context: context, calendar: calendar)
        let interval = DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1))

        let overview = try await service.load(
            bookID: fixture.book.id, section: .overview, interval: interval, baseCurrencyCode: "CNY"
        )
        let assets = try await service.load(
            bookID: fixture.book.id, section: .assets, interval: interval, baseCurrencyCode: "CNY"
        )

        XCTAssertEqual(overview.section, .overview)
        XCTAssertEqual(overview.buckets.first?.title, "第 28 周")
        XCTAssertEqual(assets.section, .assets)
        XCTAssertEqual(assets.buckets.first?.title, "现金")
    }

    func testCacheStaysStableUntilExplicitInvalidation() async throws {
        let fixture = makeFixture(bookName: "日常")
        insertExpense(10, date: date(2026, 7, 10), fixture: fixture)
        try context.save()
        let cache = StatisticsDashboardCache()
        let service = StatisticsDashboardService(context: context, calendar: calendar, cache: cache)
        let interval = DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1))
        let first = try await service.load(
            bookID: fixture.book.id, section: .categories, interval: interval, baseCurrencyCode: "CNY"
        )

        insertExpense(25, date: date(2026, 7, 11), fixture: fixture)
        try context.save()
        let cached = try await service.load(
            bookID: fixture.book.id, section: .categories, interval: interval, baseCurrencyCode: "CNY"
        )
        await service.invalidateCache()
        let refreshed = try await service.load(
            bookID: fixture.book.id, section: .categories, interval: interval, baseCurrencyCode: "CNY"
        )

        XCTAssertEqual(first.expense, 10)
        XCTAssertEqual(cached.expense, 10)
        XCTAssertEqual(refreshed.expense, 35)
    }

    func testCancelledLoadCannotPublishAStaleSnapshot() async throws {
        let fixture = makeFixture(bookName: "日常")
        insertExpense(10, date: date(2026, 7, 10), fixture: fixture)
        try context.save()
        let service = StatisticsDashboardService(
            context: context,
            calendar: calendar,
            cache: StatisticsDashboardCache()
        )
        let task = Task {
            try await service.load(
                bookID: fixture.book.id,
                section: .overview,
                interval: DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1)),
                baseCurrencyCode: "CNY"
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled work must not return a dashboard snapshot")
        } catch is CancellationError {
            // Expected: the detached aggregation and final cache write are cancellation gated.
        }
    }

    private func makeFixture(bookName: String) -> (
        book: LedgerBook, account: Account, wallet: CurrencyWallet, category: LedgerCategory
    ) {
        let book = LedgerBook(name: bookName)
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let category = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id
        )
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        return (book, account, wallet, category)
    }

    private func insertExpense(
        _ amount: Decimal,
        date: Date,
        fixture: (book: LedgerBook, account: Account, wallet: CurrencyWallet, category: LedgerCategory)
    ) {
        context.insert(LedgerTransaction(
            type: .expense,
            bookID: fixture.book.id,
            amount: amount,
            currencyCode: "CNY",
            date: date,
            sourceAccount: fixture.account,
            sourceWallet: fixture.wallet,
            category: fixture.category
        ))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
