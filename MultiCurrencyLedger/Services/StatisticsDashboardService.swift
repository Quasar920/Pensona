import Foundation
import SwiftData

struct StatisticsDashboardBucket: Identifiable, Equatable, Sendable {
    let key: String
    let title: String
    let value: Decimal
    var id: String { key }
}

struct StatisticsDashboardSnapshot: Equatable, Sendable {
    let section: StatisticsSection
    let interval: DateInterval
    let transactionCount: Int
    let total: Decimal
    let income: Decimal
    let expense: Decimal
    let buckets: [StatisticsDashboardBucket]
    let missingCodes: Set<String>

    var accessibilitySummary: String {
        let leading = AppLocalization.string(
            "共 \(transactionCount) 笔，收入 \(String(describing: income))，支出 \(String(describing: expense))，净额 \(String(describing: income - expense))。"
        )
        let detail = buckets.prefix(5).map { "\($0.title) \($0.value)" }.joined(separator: "，")
        return detail.isEmpty ? leading : "\(leading) \(detail)。"
    }
}

struct StatisticsDashboardCacheKey: Hashable, Sendable {
    let bookID: UUID
    let section: StatisticsSection
    let start: Date
    let end: Date
    let baseCurrencyCode: String
}

actor StatisticsDashboardCache {
    static let shared = StatisticsDashboardCache()
    private var snapshots: [StatisticsDashboardCacheKey: StatisticsDashboardSnapshot] = [:]

    func value(for key: StatisticsDashboardCacheKey) -> StatisticsDashboardSnapshot? {
        snapshots[key]
    }

    func insert(_ snapshot: StatisticsDashboardSnapshot, for key: StatisticsDashboardCacheKey) {
        snapshots[key] = snapshot
    }

    func invalidate() {
        snapshots.removeAll()
    }
}

private struct StatisticsTransactionDTO: Sendable {
    let id: UUID
    let date: Date
    let type: String
    let amount: Decimal
    let currencyCode: String
    let feeAmount: Decimal
    let feeCurrencyCode: String
    let adjustmentDirection: String?
    let categoryID: String
    let categoryName: String
    let accountID: String
    let accountName: String
}

private struct StatisticsRateDTO: Sendable {
    let currencyCode: String
    let baseCurrencyCode: String
    let rate: Decimal
}

@MainActor
struct StatisticsDashboardService {
    let context: ModelContext
    var calendar: Calendar = .current
    var cache: StatisticsDashboardCache = .shared

    func load(
        bookID: UUID,
        section: StatisticsSection,
        interval: DateInterval,
        baseCurrencyCode: String
    ) async throws -> StatisticsDashboardSnapshot {
        let key = StatisticsDashboardCacheKey(
            bookID: bookID,
            section: section,
            start: interval.start,
            end: interval.end,
            baseCurrencyCode: baseCurrencyCode
        )
        if let cached = await cache.value(for: key) { return cached }

        let start = interval.start
        let end = interval.end
        let predicate = #Predicate<LedgerTransaction> { transaction in
            transaction.bookID == bookID && transaction.date >= start && transaction.date < end
        }
        let rows = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\LedgerTransaction.date)]
        ))
        let transactions = rows.map { transaction in
            StatisticsTransactionDTO(
                id: transaction.id,
                date: transaction.date,
                type: transaction.typeRawValue,
                amount: transaction.sourceAmount ?? transaction.amount ?? 0,
                currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode,
                feeAmount: transaction.feeAmount ?? 0,
                feeCurrencyCode: transaction.feeCurrencyCode
                    ?? transaction.sourceCurrencyCode
                    ?? transaction.currencyCode
                    ?? baseCurrencyCode,
                adjustmentDirection: transaction.adjustmentDirectionRawValue,
                categoryID: transaction.category?.id.uuidString ?? "none",
                categoryName: transaction.category?.localizedName() ?? AppLocalization.string("未分类"),
                accountID: transaction.sourceAccount?.id.uuidString ?? "none",
                accountName: transaction.sourceAccount?.name ?? AppLocalization.string("未知账户")
            )
        }
        let rates = try context.fetch(FetchDescriptor<ExchangeRate>()).map {
            StatisticsRateDTO(currencyCode: $0.currencyCode, baseCurrencyCode: $0.baseCurrencyCode, rate: $0.rate)
        }
        let calendar = calendar

        let snapshot = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try Self.aggregate(
                transactions: transactions,
                rates: rates,
                section: section,
                interval: interval,
                baseCurrencyCode: baseCurrencyCode,
                calendar: calendar
            )
        }.value
        try Task.checkCancellation()
        await cache.insert(snapshot, for: key)
        return snapshot
    }

    func invalidateCache() async {
        await cache.invalidate()
    }

    private nonisolated static func aggregate(
        transactions: [StatisticsTransactionDTO],
        rates: [StatisticsRateDTO],
        section: StatisticsSection,
        interval: DateInterval,
        baseCurrencyCode: String,
        calendar: Calendar
    ) throws -> StatisticsDashboardSnapshot {
        var income = Decimal.zero
        var expense = Decimal.zero
        var missing = Set<String>()
        var grouped: [String: (title: String, value: Decimal)] = [:]

        for (index, transaction) in transactions.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let principal = converted(
                transaction.amount,
                code: transaction.currencyCode,
                base: baseCurrencyCode,
                rates: rates,
                missing: &missing
            ) ?? 0
            let fee = converted(
                transaction.feeAmount,
                code: transaction.feeCurrencyCode,
                base: baseCurrencyCode,
                rates: rates,
                missing: &missing
            ) ?? 0
            let signed: Decimal
            switch transaction.type {
            case TransactionKind.income.rawValue:
                income += principal
                signed = principal - fee
            case TransactionKind.expense.rawValue:
                expense += principal + fee
                signed = -principal - fee
            case TransactionKind.adjustment.rawValue:
                signed = transaction.adjustmentDirection == AdjustmentDirection.decrease.rawValue
                    ? -principal - fee
                    : principal - fee
            default:
                signed = -fee
                expense += fee
            }

            let calendarDay = calendar.startOfDay(for: transaction.date)
            let group: (String, String, Decimal) = switch section {
            case .overview:
                periodGroup(for: transaction.date, range: interval, calendar: calendar, value: signed)
            case .categories:
                (transaction.categoryID, transaction.categoryName, transaction.type == TransactionKind.expense.rawValue ? principal + fee : 0)
            case .assets:
                (transaction.accountID, transaction.accountName, signed)
            case .calendar:
                (
                    calendarDay.timeIntervalSinceReferenceDate.description,
                    calendarDay.formatted(.dateTime.month().day()),
                    signed
                )
            }
            guard group.2 != 0 else { continue }
            let current = grouped[group.0] ?? (group.1, 0)
            grouped[group.0] = (current.title, current.value + group.2)
        }

        let chronological = section == .overview || section == .calendar
        let buckets = grouped.map { StatisticsDashboardBucket(key: $0.key, title: $0.value.title, value: $0.value.value) }
            .sorted {
                chronological
                    ? (Double($0.key) ?? 0) < (Double($1.key) ?? 0)
                    : absDecimal($0.value) > absDecimal($1.value)
            }
        return StatisticsDashboardSnapshot(
            section: section,
            interval: interval,
            transactionCount: transactions.count,
            total: section == .categories ? expense : income - expense,
            income: income,
            expense: expense,
            buckets: buckets,
            missingCodes: missing
        )
    }

    private nonisolated static func periodGroup(
        for date: Date,
        range: DateInterval,
        calendar: Calendar,
        value: Decimal
    ) -> (String, String, Decimal) {
        let dayCount = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1
        let component: Calendar.Component = dayCount > 400 ? .year : dayCount > 62 ? .month : dayCount > 14 ? .weekOfYear : .day
        let start = calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
        let title: String = switch component {
        case .year: start.formatted(.dateTime.year())
        case .month: start.formatted(.dateTime.year().month())
        case .weekOfYear: AppLocalization.string( "第 \(calendar.component(.weekOfYear, from: start)) 周")
        default: start.formatted(.dateTime.month().day())
        }
        return (start.timeIntervalSinceReferenceDate.description, title, value)
    }

    private nonisolated static func converted(
        _ amount: Decimal,
        code: String,
        base: String,
        rates: [StatisticsRateDTO],
        missing: inout Set<String>
    ) -> Decimal? {
        guard amount != 0 else { return 0 }
        if code == base { return amount }
        if let direct = rates.first(where: { $0.currencyCode == code && $0.baseCurrencyCode == base }) {
            return amount * direct.rate
        }
        if let inverse = rates.first(where: { $0.currencyCode == base && $0.baseCurrencyCode == code && $0.rate != 0 }) {
            return amount / inverse.rate
        }
        missing.insert(code)
        return nil
    }

    private nonisolated static func absDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
