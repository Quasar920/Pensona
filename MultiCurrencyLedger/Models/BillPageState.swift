import Foundation

struct BillDayGroup: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]

    var id: Date { date }
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
