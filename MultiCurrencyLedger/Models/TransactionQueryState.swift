import Foundation

enum TransactionDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case thisMonth
    case last30Days
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部时间"
        case .thisMonth: "本月"
        case .last30Days: "最近 30 天"
        case .thisYear: "今年"
        case .custom: "自定义"
        }
    }
}

enum TransactionSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dateDescending
    case dateAscending
    case amountDescending
    case amountAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateDescending: "日期从新到旧"
        case .dateAscending: "日期从旧到新"
        case .amountDescending: "金额从高到低"
        case .amountAscending: "金额从低到高"
        }
    }
}

/// All transaction-list filters in one testable value. A nil book ID means the
/// user explicitly selected all books; the normal initializer defaults to the
/// current book in `LedgerScope`.
struct TransactionQueryState: Equatable, Sendable {
    var bookID: UUID?
    var dateFilter: TransactionDateFilter = .all
    var customStartDate: Date?
    var customEndDate: Date?
    var minimumAmount: Decimal?
    var maximumAmount: Decimal?
    var keyword = ""
    var accountID: UUID?
    var currencyCode: String?
    var kind: TransactionKind?
    var categoryID: UUID?
    var tagIDs: Set<UUID> = []
    var sortOrder: TransactionSortOrder = .dateDescending

    init(scope: LedgerScope) {
        bookID = scope.bookID
    }

    init(bookID: UUID? = nil) {
        self.bookID = bookID
    }

    var hasActiveFilters: Bool {
        bookID == nil
            || dateFilter != .all
            || customStartDate != nil
            || customEndDate != nil
            || minimumAmount != nil
            || maximumAmount != nil
            || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || accountID != nil
            || currencyCode != nil
            || kind != nil
            || categoryID != nil
            || !tagIDs.isEmpty
    }

    var hasValidDateRange: Bool {
        guard dateFilter == .custom,
              let customStartDate,
              let customEndDate else { return true }
        return customStartDate <= customEndDate
    }

    var hasValidAmountRange: Bool {
        guard let minimumAmount, let maximumAmount else { return true }
        return minimumAmount <= maximumAmount
    }

    mutating func clearFilters(keepingBookID bookID: UUID?) {
        self = TransactionQueryState(bookID: bookID)
    }

    func applying(
        to transactions: [LedgerTransaction],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [LedgerTransaction] {
        transactions
            .filter { matches($0, referenceDate: referenceDate, calendar: calendar) }
            .sorted(by: sort)
    }

    func matches(
        _ transaction: LedgerTransaction,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard matchesBook(transaction), matchesDate(transaction.date, referenceDate: referenceDate, calendar: calendar),
              matchesAmount(transaction), matchesKeyword(transaction), matchesAccount(transaction),
              matchesCurrency(transaction), matchesKind(transaction), matchesCategory(transaction),
              matchesTags(transaction) else {
            return false
        }
        return true
    }

    private func matchesBook(_ transaction: LedgerTransaction) -> Bool {
        guard let bookID else { return true }
        return transaction.sourceAccount?.book?.id == bookID
            || transaction.destinationAccount?.book?.id == bookID
    }

    private func matchesDate(_ date: Date, referenceDate: Date, calendar: Calendar) -> Bool {
        switch dateFilter {
        case .all:
            return true
        case .thisMonth:
            return calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -30, to: referenceDate) else { return false }
            return date >= start && date <= referenceDate
        case .thisYear:
            return calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
        case .custom:
            if let customStartDate, date < calendar.startOfDay(for: customStartDate) { return false }
            if let customEndDate {
                let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate))
                if let dayAfterEnd, date >= dayAfterEnd { return false }
            }
            return true
        }
    }

    private func matchesAmount(_ transaction: LedgerTransaction) -> Bool {
        let amount = transaction.sourceAmount ?? transaction.amount ?? .zero
        return (minimumAmount == nil || amount >= minimumAmount!)
            && (maximumAmount == nil || amount <= maximumAmount!)
    }

    private func matchesKeyword(_ transaction: LedgerTransaction) -> Bool {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [
            transaction.merchantOrCounterparty,
            transaction.note,
            transaction.category?.name,
            transaction.sourceAccount?.name,
            transaction.destinationAccount?.name
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func matchesAccount(_ transaction: LedgerTransaction) -> Bool {
        guard let accountID else { return true }
        return transaction.sourceAccount?.id == accountID || transaction.destinationAccount?.id == accountID
    }

    private func matchesCurrency(_ transaction: LedgerTransaction) -> Bool {
        guard let currencyCode else { return true }
        return transaction.sourceCurrencyCode == currencyCode
            || transaction.destinationCurrencyCode == currencyCode
            || transaction.currencyCode == currencyCode
    }

    private func matchesKind(_ transaction: LedgerTransaction) -> Bool {
        kind == nil || transaction.type == kind
    }

    private func matchesCategory(_ transaction: LedgerTransaction) -> Bool {
        categoryID == nil || transaction.category?.id == categoryID
    }

    private func matchesTags(_ transaction: LedgerTransaction) -> Bool {
        guard !tagIDs.isEmpty else { return true }
        return tagIDs.isSubset(of: Set(transaction.tags.map(\.id)))
    }

    private func sort(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction) -> Bool {
        let lhsAmount = lhs.sourceAmount ?? lhs.amount ?? .zero
        let rhsAmount = rhs.sourceAmount ?? rhs.amount ?? .zero
        switch sortOrder {
        case .dateDescending:
            return lhs.date == rhs.date ? lhs.id.uuidString > rhs.id.uuidString : lhs.date > rhs.date
        case .dateAscending:
            return lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
        case .amountDescending:
            if lhsAmount != rhsAmount { return lhsAmount > rhsAmount }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString > rhs.id.uuidString
        case .amountAscending:
            if lhsAmount != rhsAmount { return lhsAmount < rhsAmount }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
