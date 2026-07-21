import Foundation

enum ReportMetric: String, CaseIterable, Identifiable {
    case expense, income, net
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: AppLocalization.string( "支出")
        case .income: AppLocalization.string( "收入")
        case .net: AppLocalization.string( "净额")
        }
    }
}

enum ReportGranularity: String, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: AppLocalization.string( "日")
        case .weekly: AppLocalization.string( "周")
        case .monthly: AppLocalization.string( "月")
        case .yearly: AppLocalization.string( "年")
        }
    }
}

enum ReportDimension: String, CaseIterable, Identifiable {
    case category, account, book
    var id: String { rawValue }
    var title: String {
        switch self {
        case .category: AppLocalization.string( "分类")
        case .account: AppLocalization.string( "账户")
        case .book: AppLocalization.string( "账本")
        }
    }
}

struct ReportBucket: Identifiable, Equatable {
    let key: String
    let title: String
    let value: Decimal
    var id: String { key }
}

struct ReportResult {
    let total: Decimal
    let buckets: [ReportBucket]
    let missingCodes: Set<String>
}

struct ReportQueryService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    var calendar: Calendar = .current

    func trend(
        transactions: [LedgerTransaction],
        relations: [TransactionRelation],
        interval: DateInterval,
        metric: ReportMetric,
        granularity: ReportGranularity,
        aaSplits: [AASplit] = [],
        aaSettlements: [AASettlement] = []
    ) -> ReportResult {
        aggregate(
            transactions: transactions,
            relations: relations,
            aaSplits: aaSplits,
            aaSettlements: aaSettlements,
            interval: interval,
            metric: metric
        ) { transaction, _ in
            let start = periodStart(granularity, date: transaction.date)
            return [(key: start.timeIntervalSinceReferenceDate.description, title: periodTitle(granularity, date: start))]
        }
    }

    func breakdown(
        transactions: [LedgerTransaction],
        relations: [TransactionRelation],
        interval: DateInterval,
        metric: ReportMetric,
        dimension: ReportDimension,
        books: [LedgerBook] = [],
        aaSplits: [AASplit] = [],
        aaSettlements: [AASettlement] = []
    ) -> ReportResult {
        let bookNames = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.name) })
        return aggregate(
            transactions: transactions,
            relations: relations,
            aaSplits: aaSplits,
            aaSettlements: aaSettlements,
            interval: interval,
            metric: metric
        ) { transaction, originalForRecovery in
            let semantic = originalForRecovery ?? transaction
            switch dimension {
            case .category:
                return [(semantic.category?.id.uuidString ?? "none", semantic.category?.name ?? AppLocalization.string("未分类"))]
            case .account:
                return [(semantic.sourceAccount?.id.uuidString ?? "none", semantic.sourceAccount?.name ?? AppLocalization.string("未知账户"))]
            case .book:
                guard let bookID = semantic.bookID else { return [("none", "未知账本")] }
                return [(bookID.uuidString, bookNames[bookID] ?? AppLocalization.string("未知账本"))]
            }
        }
    }

    private func aggregate(
        transactions: [LedgerTransaction],
        relations: [TransactionRelation],
        aaSplits: [AASplit],
        aaSettlements: [AASettlement],
        interval: DateInterval,
        metric: ReportMetric,
        group: (LedgerTransaction, LedgerTransaction?) -> [(key: String, title: String)]
    ) -> ReportResult {
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let relationByRelatedID = Dictionary(uniqueKeysWithValues: relations.map { ($0.relatedTransactionID, $0) })
        let aaSplitByOriginalID = Dictionary(uniqueKeysWithValues: aaSplits.map {
            ($0.originalTransactionID, $0)
        })
        let aaRecoveryIDs = Set(aaSettlements.map(\.recoveryTransactionID))
        var values: [String: (title: String, value: Decimal)] = [:]
        var missing = Set<String>()

        for transaction in transactions
        where contains(transaction.date, in: interval) {
            let recoveryRelation = relationByRelatedID[transaction.id]
            let original = recoveryRelation.flatMap { byID[$0.originalTransactionID] }
            let signed = signedValue(
                transaction,
                recoveryRelation: recoveryRelation,
                aaSplit: aaSplitByOriginalID[transaction.id],
                isAARecovery: aaRecoveryIDs.contains(transaction.id),
                metric: metric,
                valuation: valuation,
                missing: &missing
            )
            guard signed != 0 else { continue }
            for item in group(transaction, original) {
                let current = values[item.key] ?? (item.title, 0)
                values[item.key] = (current.title, current.value + signed)
            }
        }
        let buckets = values.map { ReportBucket(key: $0.key, title: $0.value.title, value: $0.value.value) }
            .sorted { left, right in
                if left.key.hasPrefix("-") || left.key.first?.isNumber == true {
                    return left.key < right.key
                }
                return absDecimal(left.value) > absDecimal(right.value)
            }
        return ReportResult(
            total: buckets.reduce(Decimal.zero) { $0 + $1.value },
            buckets: buckets,
            missingCodes: missing
        )
    }

    private func signedValue(
        _ transaction: LedgerTransaction,
        recoveryRelation: TransactionRelation?,
        aaSplit: AASplit?,
        isAARecovery: Bool,
        metric: ReportMetric,
        valuation: ValuationService,
        missing: inout Set<String>
    ) -> Decimal {
        if isAARecovery { return 0 }
        let rawAmount = recoveryRelation?.amount ?? transaction.sourceAmount ?? transaction.amount ?? 0
        let amount = transaction.type == .expense
            ? max(0, rawAmount - (aaSplit?.othersOwedAmount ?? 0))
            : rawAmount
        let code = transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode
        guard let principal = convert(amount, code: code, valuation: valuation, missing: &missing) else { return 0 }
        let fee: Decimal = transaction.feeAmount.flatMap {
            convert(
                $0,
                code: transaction.feeCurrencyCode ?? code,
                valuation: valuation,
                missing: &missing
            )
        } ?? 0

        switch metric {
        case .expense:
            if recoveryRelation != nil { return -principal }
            return transaction.type == .expense ? principal + fee : fee
        case .income:
            return transaction.type == .income && recoveryRelation == nil ? principal : 0
        case .net:
            if recoveryRelation != nil { return principal }
            switch transaction.type {
            case .income: return principal - fee
            case .expense: return -principal - fee
            case .adjustment:
                return (transaction.adjustmentDirection == .decrease ? -principal : principal) - fee
            case .transfer, .exchange: return -fee
            }
        }
    }

    private func convert(
        _ amount: Decimal,
        code: String,
        valuation: ValuationService,
        missing: inout Set<String>
    ) -> Decimal? {
        guard let result = valuation.value(amount, currencyCode: code) else {
            missing.insert(code)
            return nil
        }
        return result
    }

    private func periodStart(_ granularity: ReportGranularity, date: Date) -> Date {
        let component: Calendar.Component = switch granularity {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        return calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func periodTitle(_ granularity: ReportGranularity, date: Date) -> String {
        switch granularity {
        case .daily: date.formatted(.dateTime.month().day())
        case .weekly: AppLocalization.string( "第 \(calendar.component(.weekOfYear, from: date)) 周")
        case .monthly: date.formatted(.dateTime.year().month())
        case .yearly: date.formatted(.dateTime.year())
        }
    }

    private func absDecimal(_ value: Decimal) -> Decimal { value < 0 ? -value : value }

    /// All report ranges use the same half-open boundary rule as the statistics dashboard.
    func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}
