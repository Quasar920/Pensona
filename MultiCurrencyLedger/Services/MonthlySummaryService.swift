import Foundation

struct MonthlySummary: Equatable {
    let monthStart: Date
    let currencyCode: String
    let income: Decimal
    let expense: Decimal
    let budget: Decimal?
    let missingCodes: Set<String>

    var remainingBudget: Decimal? {
        budget.map { $0 - expense }
    }

    var isOverBudget: Bool {
        remainingBudget.map { $0 < 0 } ?? false
    }

    var incomeProgress: Double {
        relativeProgress(for: income)
    }

    var expenseProgress: Double {
        relativeProgress(for: expense)
    }

    var budgetProgress: Double {
        guard let budget, budget > 0 else { return 0 }
        let rawValue = NSDecimalNumber(decimal: expense / budget).doubleValue
        return min(max(rawValue, 0), 1)
    }

    var remainingBudgetProgress: Double? {
        guard let budget, budget > 0 else { return nil }
        let rawValue = NSDecimalNumber(decimal: (budget - expense) / budget).doubleValue
        return min(max(rawValue, 0), 1)
    }

    var hasCompleteConversion: Bool {
        missingCodes.isEmpty
    }

    private var largestCashFlow: Decimal {
        max(income, expense)
    }

    private func relativeProgress(for value: Decimal) -> Double {
        guard value > 0, largestCashFlow > 0 else { return 0 }
        let rawValue = NSDecimalNumber(decimal: value / largestCashFlow).doubleValue
        return min(max(rawValue, 0), 1)
    }
}

typealias MonthlySummaryResult = MonthlySummary

struct MonthlySummaryService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    var calendar: Calendar = .current

    func summary(
        for transactions: [LedgerTransaction],
        month date: Date,
        budget: Decimal? = nil,
        relations: [TransactionRelation] = [],
        aaSplits: [AASplit] = [],
        aaSettlements: [AASettlement] = []
    ) -> MonthlySummary {
        let interval = calendar.dateInterval(of: .month, for: date)
        let monthStart = interval?.start ?? calendar.startOfDay(for: date)
        let monthEnd = interval?.end
            ?? calendar.date(byAdding: .month, value: 1, to: monthStart)
            ?? .distantFuture
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        var income = Decimal.zero
        var expense = Decimal.zero
        var missingCodes = Set<String>()
        let relationByRelatedIncomeID = Dictionary(uniqueKeysWithValues: relations
            .filter { $0.amount > 0 || ($0.kind == .refund && $0.excessIncomeTransactionID == nil) }
            .map { ($0.relatedTransactionID, $0) })
        let aaRecoveryIDs = Set(aaSettlements.map(\.recoveryTransactionID))
        let aaSplitByOriginalID = Dictionary(uniqueKeysWithValues: aaSplits.map {
            ($0.originalTransactionID, $0)
        })

        for transaction in transactions
        where transaction.date >= monthStart && transaction.date < monthEnd {
            let exclusion = MonthlySummaryExclusionStore.exclusion(for: transaction.id)
            let principal = transaction.type == .expense
                ? transaction.netExpenseAmount
                : transaction.sourceAmount ?? transaction.amount ?? 0
            let principalCode = transaction.sourceCurrencyCode
                ?? transaction.currencyCode
                ?? baseCurrencyCode

            switch transaction.type {
            case .income:
                if exclusion.income {
                    break
                } else if aaRecoveryIDs.contains(transaction.id) {
                    break
                } else if let relation = relationByRelatedIncomeID[transaction.id] {
                    add(
                        -relation.amount,
                        currencyCode: principalCode,
                        to: &expense,
                        missingCodes: &missingCodes,
                        valuation: valuation
                    )
                    if relation.kind == .refund,
                       relation.excessIncomeTransactionID == nil,
                       let excess = relation.excessIncomeAmount,
                       excess > 0 {
                        add(
                            excess,
                            currencyCode: principalCode,
                            to: &income,
                            missingCodes: &missingCodes,
                            valuation: valuation
                        )
                    }
                } else {
                    add(
                        principal,
                        currencyCode: principalCode,
                        to: &income,
                        missingCodes: &missingCodes,
                        valuation: valuation
                    )
                }
            case .expense:
                guard !exclusion.expense else { continue }
                let personalAmount = max(
                    0,
                    principal - (aaSplitByOriginalID[transaction.id]?.othersOwedAmount ?? 0)
                )
                add(
                    personalAmount,
                    currencyCode: principalCode,
                    to: &expense,
                    missingCodes: &missingCodes,
                    valuation: valuation
                )
            case .transfer, .exchange, .adjustment:
                break
            }

            if transaction.type != .income,
               let fee = transaction.feeAmount, fee != 0 {
                add(
                    fee,
                    currencyCode: transaction.feeCurrencyCode ?? principalCode,
                    to: &expense,
                    missingCodes: &missingCodes,
                    valuation: valuation
                )
            }
        }

        return MonthlySummary(
            monthStart: monthStart,
            currencyCode: baseCurrencyCode,
            income: income,
            expense: expense,
            budget: budget.flatMap { $0 > 0 ? $0 : nil },
            missingCodes: missingCodes
        )
    }

    private func add(
        _ amount: Decimal,
        currencyCode: String,
        to total: inout Decimal,
        missingCodes: inout Set<String>,
        valuation: ValuationService
    ) {
        guard amount != 0 else { return }
        if let converted = valuation.value(amount, currencyCode: currencyCode) {
            total += converted
        } else {
            missingCodes.insert(currencyCode)
        }
    }
}
