import Foundation

enum BillSearchTimeRange: Equatable, Sendable {
    case all
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case custom(start: Date, end: Date)

    var title: String {
        switch self {
        case .all: return "时间"
        case .today: return "今天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisYear: return "本年"
        case let .custom(start, end):
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: start))～\(formatter.string(from: end))"
        }
    }
}

enum BillSearchSortMode: String, CaseIterable, Identifiable, Sendable {
    case dateDescending
    case dateAscending
    case amountDescending
    case amountAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateDescending: return "时间从新到旧"
        case .dateAscending: return "时间从旧到新"
        case .amountDescending: return "金额从高到低"
        case .amountAscending: return "金额从低到高"
        }
    }

    var compactTitle: String {
        switch self {
        case .dateDescending: return "排序"
        case .dateAscending: return "时间升序"
        case .amountDescending: return "金额降序"
        case .amountAscending: return "金额升序"
        }
    }

    var usesDayGrouping: Bool {
        self == .dateDescending || self == .dateAscending
    }
}

struct BillSearchQuery: Equatable, Sendable {
    var keyword = ""
    var timeRange: BillSearchTimeRange = .all
    var minimumAmount: Decimal?
    var maximumAmount: Decimal?
    var bookID: UUID?
    var accountIDs = Set<UUID>()
    var sortMode: BillSearchSortMode = .dateDescending

    var normalizedTokens: [String] {
        var seen = Set<String>()
        return keyword
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
    }

    var hasSearchCriteria: Bool {
        !normalizedTokens.isEmpty || timeRange != .all || minimumAmount != nil
            || maximumAmount != nil || bookID != nil || !accountIDs.isEmpty
    }

    var normalizedKeyword: String { normalizedTokens.joined(separator: " ") }

    mutating func reset() { self = BillSearchQuery() }
}

struct BillSearchAmountAndCount: Equatable {
    var amount = Decimal.zero
    var count = 0
}

enum BillSearchDynamicCategory: String, CaseIterable, Identifiable, Hashable {
    case transfer, discount, recharge, pendingReimbursement, reimbursed
    case reimbursementIncome, refund, refundIncome, repayment, collection, fee

    var id: String { rawValue }
    var title: String {
        switch self {
        case .transfer: return "转账"
        case .discount: return "优惠"
        case .recharge: return "充值"
        case .pendingReimbursement: return "待报销"
        case .reimbursed: return "已报销"
        case .reimbursementIncome: return "报销收入"
        case .refund: return "退款"
        case .refundIncome: return "退款收入"
        case .repayment: return "还款"
        case .collection: return "收款"
        case .fee: return "手续费"
        }
    }
}

struct BillSearchDynamicSummary: Identifiable {
    let category: BillSearchDynamicCategory
    let amount: Decimal
    let count: Int

    var id: BillSearchDynamicCategory { category }
}

struct BillSearchResult {
    let allTransactions: [LedgerTransaction]
    let totalCount: Int
    let income: BillSearchAmountAndCount
    let expense: BillSearchAmountAndCount
    let dynamicSummaries: [BillSearchDynamicSummary]

    func page(offset: Int, size: Int) -> [LedgerTransaction] {
        guard offset < allTransactions.count else { return [] }
        return Array(allTransactions[offset..<min(offset + size, allTransactions.count)])
    }
}
