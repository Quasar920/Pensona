import Foundation

/// Display-only refund state for the original expense row. The accounting
/// records remain separate transactions; this lets the receipt view show the
/// same fully-offset presentation as the reference app.
struct RefundDisplaySummary: Equatable {
    let recoveredAmount: Decimal
    let excessIncomeAmount: Decimal
    let originalNetAmount: Decimal

    var isFullyOffset: Bool { recoveredAmount >= originalNetAmount && originalNetAmount > 0 }
}

/// A system-generated ledger line derived from a refund relation. It is kept
/// balance-neutral because the cash itself is already represented by the
/// linked "退款" transaction.
struct RefundIncomeDisplay: Identifiable, Equatable {
    let id: UUID
    let refundDepositTransactionID: UUID
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let merchant: String
    let accountName: String
}

struct BillDayGroup: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]
    let income: Decimal
    let expense: Decimal
    let refundDisplays: [UUID: RefundDisplaySummary]
    let refundIncomeDisplays: [UUID: RefundIncomeDisplay]

    var id: Date { date }

    init(
        date: Date,
        transactions: [LedgerTransaction],
        income: Decimal = 0,
        expense: Decimal = 0,
        refundDisplays: [UUID: RefundDisplaySummary] = [:],
        refundIncomeDisplays: [UUID: RefundIncomeDisplay] = [:]
    ) {
        self.date = date
        self.transactions = transactions
        self.income = income
        self.expense = expense
        self.refundDisplays = refundDisplays
        self.refundIncomeDisplays = refundIncomeDisplays
    }
}

struct BillPageSnapshot {
    let bookID: UUID
    let monthInterval: DateInterval
    let transactions: [LedgerTransaction]
    let dayGroups: [BillDayGroup]
    let summary: MonthlySummary

    static func empty(
        bookID: UUID,
        month: Date,
        baseCurrencyCode: String,
        calendar: Calendar = .current
    ) -> BillPageSnapshot {
        let interval = calendar.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 0)
        return BillPageSnapshot(
            bookID: bookID,
            monthInterval: interval,
            transactions: [],
            dayGroups: [],
            summary: MonthlySummary(
                monthStart: interval.start,
                currencyCode: baseCurrencyCode,
                income: 0,
                expense: 0,
                budget: nil,
                missingCodes: []
            )
        )
    }
}

struct BillPageState: Equatable {
    var selectedMonth: Date
    var searchText = ""
    var isSearchExpanded = false

    init(selectedMonth: Date = .now) {
        self.selectedMonth = selectedMonth
    }

    mutating func changeMonth(by offset: Int, calendar: Calendar = .current) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        selectedMonth = next
    }

    mutating func collapseSearch() {
        searchText = ""
        isSearchExpanded = false
    }
}
