import Foundation
import SwiftData

enum BudgetError: LocalizedError, Equatable {
    case invalidAmount
    case invalidCategory

    var errorDescription: String? {
        switch self {
        case .invalidAmount: AppLocalization.string( "预算金额必须大于 0")
        case .invalidCategory: AppLocalization.string( "分类预算必须使用当前账本的支出分类")
        }
    }
}

struct BudgetStatus: Identifiable {
    let budget: MonthlyBudget
    let spent: Decimal
    let missingCodes: Set<String>

    var id: UUID { budget.id }
    var remaining: Decimal { budget.amount - spent }
    var progress: Double {
        guard budget.amount > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budget.amount).doubleValue
    }
    var isOver: Bool { remaining < 0 }
}

@MainActor
final class BudgetService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func budgets(
        bookID: UUID,
        period: BudgetPeriod,
        containing date: Date,
        currencyCode: String
    ) throws -> [MonthlyBudget] {
        let start = periodStart(period, containing: date)
        return try context.fetch(FetchDescriptor<MonthlyBudget>()).filter {
            $0.bookID == bookID
                && $0.period == period
                && $0.currencyCode == normalized(currencyCode)
                && calendar.isDate($0.monthStart, inSameDayAs: start)
        }
    }

    @discardableResult
    func upsert(
        amount: Decimal,
        bookID: UUID,
        period: BudgetPeriod,
        containing date: Date,
        currencyCode: String,
        categoryID: UUID? = nil
    ) throws -> MonthlyBudget {
        guard amount > 0 else { throw BudgetError.invalidAmount }
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        if let categoryID {
            let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
            guard categories.contains(where: {
                $0.id == categoryID
                    && $0.type == .expense
                    && !$0.isArchived
            }) else { throw BudgetError.invalidCategory }
        }
        let start = periodStart(period, containing: date)
        let code = normalized(currencyCode)
        let key = scopeKey(
            bookID: bookID,
            period: period,
            start: start,
            currencyCode: code,
            categoryID: categoryID
        )
        if let existing = try context.fetch(FetchDescriptor<MonthlyBudget>())
            .first(where: { $0.scopeKey == key }) {
            existing.amount = amount
            existing.monthStart = start
            existing.periodRawValue = period.rawValue
            existing.categoryID = categoryID
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        let budget = MonthlyBudget(
            scopeKey: key,
            bookID: bookID,
            monthStart: start,
            currencyCode: code,
            amount: amount,
            period: period,
            categoryID: categoryID
        )
        context.insert(budget)
        try context.save()
        return budget
    }

    func remove(_ budget: MonthlyBudget) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: budget.bookID)
        context.delete(budget)
        try context.save()
    }

    @discardableResult
    func copyPrevious(
        bookID: UUID,
        period: BudgetPeriod,
        containing date: Date,
        currencyCode: String
    ) throws -> [MonthlyBudget] {
        let currentStart = periodStart(period, containing: date)
        let component: Calendar.Component = switch period {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        guard let previousDate = calendar.date(byAdding: component, value: -1, to: currentStart) else {
            return []
        }
        let previous = try budgets(
            bookID: bookID,
            period: period,
            containing: previousDate,
            currencyCode: currencyCode
        )
        return try previous.map {
            try upsert(
                amount: $0.amount,
                bookID: bookID,
                period: period,
                containing: currentStart,
                currencyCode: currencyCode,
                categoryID: $0.categoryID
            )
        }
    }

    func periodStart(_ period: BudgetPeriod, containing date: Date) -> Date {
        switch period {
        case .weekly:
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .monthly:
            calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        case .yearly:
            calendar.dateInterval(of: .year, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    func interval(for budget: MonthlyBudget) -> DateInterval {
        let component: Calendar.Component = switch budget.period {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        return calendar.dateInterval(of: component, for: budget.monthStart)
            ?? DateInterval(start: budget.monthStart, duration: 0)
    }

    private func scopeKey(
        bookID: UUID,
        period: BudgetPeriod,
        start: Date,
        currencyCode: String,
        categoryID: UUID?
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        if period == .monthly, categoryID == nil {
            // Preserve the original monthly-total key so existing installs migrate in place.
            return "\(bookID.uuidString.lowercased())|\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))|\(currencyCode)"
        }
        let date = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return [
            bookID.uuidString.lowercased(), period.rawValue, date, currencyCode,
            categoryID?.uuidString.lowercased() ?? "all"
        ].joined(separator: "|")
    }

    private func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct BudgetStatisticsService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    var calendar: Calendar = .current

    func status(
        for budget: MonthlyBudget,
        transactions: [LedgerTransaction],
        relations: [TransactionRelation],
        aaSplits: [AASplit] = []
    ) -> BudgetStatus {
        let serviceInterval = interval(for: budget)
        let bookTransactions = transactions.filter {
            $0.bookID == budget.bookID && serviceInterval.contains($0.date)
        }
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        var spent = Decimal.zero
        var missingCodes = Set<String>()
        let aaSplitByOriginalID = Dictionary(uniqueKeysWithValues: aaSplits.map {
            ($0.originalTransactionID, $0)
        })

        for transaction in bookTransactions {
            let categoryMatches = budget.categoryID == nil || transaction.category?.id == budget.categoryID
            if transaction.type == .expense, categoryMatches {
                add(
                    max(
                        0,
                        (transaction.sourceAmount ?? transaction.amount ?? 0)
                            - (aaSplitByOriginalID[transaction.id]?.othersOwedAmount ?? 0)
                    ),
                    code: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode,
                    sign: 1,
                    total: &spent,
                    missing: &missingCodes,
                    valuation: valuation
                )
            }
            if let fee = transaction.feeAmount,
               budget.categoryID == nil || categoryMatches {
                add(
                    fee,
                    code: transaction.feeCurrencyCode ?? transaction.sourceCurrencyCode ?? baseCurrencyCode,
                    sign: 1,
                    total: &spent,
                    missing: &missingCodes,
                    valuation: valuation
                )
            }
        }

        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        for relation in relations {
            guard let original = byID[relation.originalTransactionID],
                  let related = byID[relation.relatedTransactionID],
                  serviceInterval.contains(related.date),
                  original.bookID == budget.bookID,
                  budget.categoryID == nil || original.category?.id == budget.categoryID else { continue }
            add(
                relation.amount,
                code: related.sourceCurrencyCode ?? related.currencyCode ?? baseCurrencyCode,
                sign: -1,
                total: &spent,
                missing: &missingCodes,
                valuation: valuation
            )
        }

        return BudgetStatus(budget: budget, spent: spent, missingCodes: missingCodes)
    }

    private func interval(for budget: MonthlyBudget) -> DateInterval {
        let component: Calendar.Component = switch budget.period {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        return calendar.dateInterval(of: component, for: budget.monthStart)
            ?? DateInterval(start: budget.monthStart, duration: 0)
    }

    private func add(
        _ amount: Decimal,
        code: String,
        sign: Decimal,
        total: inout Decimal,
        missing: inout Set<String>,
        valuation: ValuationService
    ) {
        if let value = valuation.value(amount, currencyCode: code) {
            total += sign * value
        } else {
            missing.insert(code)
        }
    }
}
