import XCTest
@testable import MultiCurrencyLedger

final class TransactionQueryStateTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testAppliesCompoundBookDateAmountKeywordAccountCurrencyKindAndCategoryFilters() {
        let book = LedgerBook(name: "日常")
        let otherBook = LedgerBook(name: "旅行")
        let account = Account(name: "招商银行工资卡", type: .bankCard, book: book)
        let otherAccount = Account(name: "旅行现金", type: .cash, book: otherBook)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let otherWallet = CurrencyWallet(currency: .CNY, account: otherAccount)
        let dining = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        let shopping = LedgerCategory(name: "购物", type: .expense, symbolName: "bag", sortOrder: 1)

        let matching = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 88,
            currencyCode: "CNY",
            date: date("2026-07-12T08:00:00Z"),
            note: "午餐",
            sourceAccount: account,
            sourceWallet: wallet,
            sourceAmount: 88,
            sourceCurrencyCode: "CNY",
            category: dining,
            merchantOrCounterparty: "海底捞"
        )
        let wrongBook = LedgerTransaction(
            type: .expense,
            bookID: otherBook.id,
            amount: 88,
            date: matching.date,
            note: "海底捞午餐",
            sourceAccount: otherAccount,
            sourceWallet: otherWallet,
            sourceAmount: 88,
            sourceCurrencyCode: "CNY",
            category: dining
        )
        let wrongAmount = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 188,
            date: matching.date,
            note: "海底捞午餐",
            sourceAccount: account,
            sourceWallet: wallet,
            sourceAmount: 188,
            sourceCurrencyCode: "CNY",
            category: dining
        )
        let wrongCategory = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 88,
            date: matching.date,
            note: "海底捞午餐",
            sourceAccount: account,
            sourceWallet: wallet,
            sourceAmount: 88,
            sourceCurrencyCode: "CNY",
            category: shopping
        )

        var query = TransactionQueryState(bookID: book.id)
        query.dateFilter = .custom
        query.customStartDate = date("2026-07-12T00:00:00Z")
        query.customEndDate = date("2026-07-12T00:00:00Z")
        query.minimumAmount = 80
        query.maximumAmount = 100
        query.keyword = " 海底捞 "
        query.accountID = account.id
        query.currencyCode = "CNY"
        query.kind = .expense
        query.categoryID = dining.id

        XCTAssertEqual(
            query.applying(
                to: [wrongBook, wrongAmount, wrongCategory, matching],
                referenceDate: date("2026-07-13T00:00:00Z"),
                calendar: calendar
            ).map(\.id),
            [matching.id]
        )
    }

    func testCustomDateIncludesEntireEndDayAndExcludesFollowingMidnight() {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let beforeEnd = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            date: date("2026-07-12T23:59:59Z"),
            sourceAccount: account
        )
        let followingMidnight = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            date: date("2026-07-13T00:00:00Z"),
            sourceAccount: account
        )
        var query = TransactionQueryState(bookID: book.id)
        query.dateFilter = .custom
        query.customStartDate = date("2026-07-12T12:30:00Z")
        query.customEndDate = date("2026-07-12T12:30:00Z")

        XCTAssertEqual(
            query.applying(
                to: [followingMidnight, beforeEnd],
                referenceDate: date("2026-07-13T00:00:00Z"),
                calendar: calendar
            ).map(\.id),
            [beforeEnd.id]
        )
    }

    func testAmountSortUsesIDAsDeterministicFinalTieBreaker() {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = LedgerTransaction(
            id: lowerID,
            type: .expense,
            bookID: book.id,
            amount: 10,
            date: date("2026-07-12T08:00:00Z"),
            sourceAccount: account,
            sourceAmount: 10
        )
        let second = LedgerTransaction(
            id: higherID,
            type: .expense,
            bookID: book.id,
            amount: 10,
            date: first.date,
            sourceAccount: account,
            sourceAmount: 10
        )
        var query = TransactionQueryState(bookID: book.id)
        query.sortOrder = .amountAscending

        XCTAssertEqual(
            query.applying(to: [second, first], calendar: calendar).map(\.id),
            [lowerID, higherID]
        )

        query.sortOrder = .amountDescending
        XCTAssertEqual(
            query.applying(to: [first, second], calendar: calendar).map(\.id),
            [higherID, lowerID]
        )
    }

    func testClearFiltersKeepsCurrentBookAndResetsSort() {
        let bookID = UUID()
        var query = TransactionQueryState(bookID: bookID)
        query.keyword = "咖啡"
        query.minimumAmount = 10
        query.sortOrder = .amountDescending

        query.clearFilters(keepingBookID: bookID)

        XCTAssertEqual(query.bookID, bookID)
        XCTAssertFalse(query.hasActiveFilters)
        XCTAssertEqual(query.sortOrder, .dateDescending)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
