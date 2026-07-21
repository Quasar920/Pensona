import Foundation

/// The common data boundary used by book, month, and budget features.
///
/// This is deliberately a value type: callers provide the data to inspect and
/// it never reads SwiftData or owns SwiftUI state.
struct LedgerScope: Equatable, Sendable {
    let bookID: UUID
    let selectedMonth: Date
    let baseCurrencyCode: String
    let calendar: Calendar

    init(
        bookID: UUID,
        selectedMonth: Date,
        baseCurrencyCode: String,
        calendar: Calendar = .current
    ) {
        self.bookID = bookID
        self.calendar = calendar
        self.selectedMonth = calendar.dateInterval(of: .month, for: selectedMonth)?.start
            ?? calendar.startOfDay(for: selectedMonth)
        self.baseCurrencyCode = baseCurrencyCode
    }

    var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: selectedMonth, duration: 0)
    }

    func contains(date: Date) -> Bool {
        let interval = monthInterval
        return date >= interval.start && date < interval.end
    }

    func contains(transaction: LedgerTransaction) -> Bool {
        contains(date: transaction.date)
            && transactionBelongsToBook(transaction)
    }

    func matches(budget: MonthlyBudget) -> Bool {
        budget.bookID == bookID
            && budget.period == .monthly
            && budget.categoryID == nil
            && budget.currencyCode == baseCurrencyCode
            && calendar.isDate(budget.monthStart, equalTo: selectedMonth, toGranularity: .month)
    }

    func transactionBelongsToBook(_ transaction: LedgerTransaction) -> Bool {
        transaction.bookID == bookID
    }
}
