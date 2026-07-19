import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class LedgerScopeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, AASplit.self, AASettlement.self,
            ExchangeRate.self, MonthlyBudget.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testScopeKeepsTransactionsAndBudgetsInTheSameBookMonthAndCurrency() throws {
        let dailyBook = LedgerBook(name: "日常")
        let travelBook = LedgerBook(name: "旅行")
        let dailyAccount = Account(name: "日常账户", type: .cash, book: dailyBook)
        let travelAccount = Account(name: "旅行账户", type: .cash, book: travelBook)
        let dailyTransaction = LedgerTransaction(
            type: .expense,
            date: date("2026-02-18T12:00:00Z"),
            sourceAccount: dailyAccount
        )
        let wrongBook = LedgerTransaction(
            type: .expense,
            date: date("2026-02-18T12:00:00Z"),
            sourceAccount: travelAccount
        )
        let wrongMonth = LedgerTransaction(
            type: .expense,
            date: date("2026-03-01T00:00:00Z"),
            sourceAccount: dailyAccount
        )
        let matchingBudget = MonthlyBudget(
            scopeKey: "daily-feb-cny", bookID: dailyBook.id,
            monthStart: date("2026-02-01T00:00:00Z"), currencyCode: "CNY", amount: 1_000
        )
        let wrongCurrencyBudget = MonthlyBudget(
            scopeKey: "daily-feb-usd", bookID: dailyBook.id,
            monthStart: date("2026-02-01T00:00:00Z"), currencyCode: "USD", amount: 1_000
        )
        let wrongMonthBudget = MonthlyBudget(
            scopeKey: "daily-mar-cny", bookID: dailyBook.id,
            monthStart: date("2026-03-01T00:00:00Z"), currencyCode: "CNY", amount: 1_000
        )
        context.insert(dailyBook)
        context.insert(travelBook)
        context.insert(dailyAccount)
        context.insert(travelAccount)
        context.insert(dailyTransaction)
        context.insert(wrongBook)
        context.insert(wrongMonth)
        context.insert(matchingBudget)
        context.insert(wrongCurrencyBudget)
        context.insert(wrongMonthBudget)
        try context.save()

        let scope = LedgerScope(
            bookID: dailyBook.id,
            selectedMonth: date("2026-02-15T08:00:00Z"),
            baseCurrencyCode: "CNY",
            calendar: calendar
        )

        XCTAssertEqual([dailyTransaction, wrongBook, wrongMonth].filter(scope.contains).map(\.id), [dailyTransaction.id])
        XCTAssertEqual(
            [matchingBudget, wrongCurrencyBudget, wrongMonthBudget].filter(scope.matches).map(\.id),
            [matchingBudget.id]
        )
    }

    func testScopeIncludesDestinationBookForTransfersAndExcludesMonthBoundary() {
        let sourceBook = LedgerBook(name: "来源")
        let destinationBook = LedgerBook(name: "目标")
        let source = Account(name: "来源账户", type: .cash, book: sourceBook)
        let destination = Account(name: "目标账户", type: .cash, book: destinationBook)
        let incomingTransfer = LedgerTransaction(
            type: .transfer,
            date: date("2026-02-28T23:59:59Z"),
            sourceAccount: source,
            destinationAccount: destination
        )
        let nextMonthTransfer = LedgerTransaction(
            type: .transfer,
            date: date("2026-03-01T00:00:00Z"),
            sourceAccount: source,
            destinationAccount: destination
        )
        let scope = LedgerScope(
            bookID: destinationBook.id,
            selectedMonth: date("2026-02-03T00:00:00Z"),
            baseCurrencyCode: "CNY",
            calendar: calendar
        )

        XCTAssertTrue(scope.contains(transaction: incomingTransfer))
        XCTAssertFalse(scope.contains(transaction: nextMonthTransfer))
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}
