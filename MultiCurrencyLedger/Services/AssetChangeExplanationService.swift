import Foundation

struct AssetChangeExplanation {
    let openingNetWorth: Decimal
    let currentNetWorth: Decimal
    let income: Decimal
    let expense: Decimal
    let expenseRecovery: Decimal
    let fees: Decimal
    let adjustments: Decimal
    let exchangeImpact: Decimal
    let missingCodes: Set<String>

    var netChange: Decimal { currentNetWorth - openingNetWorth }
    var explainedChange: Decimal {
        income + expenseRecovery - expense - fees + adjustments + exchangeImpact
    }
    var unexplained: Decimal { netChange - explainedChange }
}

struct AssetChangeExplanationService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]

    func explain(
        accounts: [Account],
        transactions: [LedgerTransaction],
        relations: [TransactionRelation],
        interval: DateInterval
    ) -> AssetChangeExplanation {
        let current = AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(for: accounts).ownerEquity
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        let relationByRelatedID = Dictionary(uniqueKeysWithValues: relations.map {
            ($0.relatedTransactionID, $0)
        })
        var income = Decimal.zero
        var expense = Decimal.zero
        var recovery = Decimal.zero
        var fees = Decimal.zero
        var adjustments = Decimal.zero
        var exchangeImpact = Decimal.zero
        var missing = Set<String>()

        for transaction in transactions where interval.contains(transaction.date) {
            let amount = transaction.sourceAmount ?? transaction.amount ?? 0
            let code = transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode
            switch transaction.type {
            case .income:
                if let value = converted(amount, code: code, valuation: valuation, missing: &missing) {
                    if relationByRelatedID[transaction.id] != nil { recovery += value }
                    else { income += value }
                }
            case .expense:
                if let value = converted(amount, code: code, valuation: valuation, missing: &missing) {
                    expense += value
                }
            case .adjustment:
                if let value = converted(amount, code: code, valuation: valuation, missing: &missing) {
                    adjustments += transaction.adjustmentDirection == .decrease ? -value : value
                }
            case .exchange:
                let source = converted(amount, code: code, valuation: valuation, missing: &missing)
                let destination = converted(
                    transaction.destinationAmount ?? 0,
                    code: transaction.destinationCurrencyCode ?? baseCurrencyCode,
                    valuation: valuation,
                    missing: &missing
                )
                if let source, let destination { exchangeImpact += destination - source }
            case .transfer:
                break
            }
            if let fee = transaction.feeAmount,
               let value = converted(
                fee,
                code: transaction.feeCurrencyCode ?? code,
                valuation: valuation,
                missing: &missing
               ) {
                fees += value
            }
        }
        let explained = income + recovery - expense - fees + adjustments + exchangeImpact
        return AssetChangeExplanation(
            openingNetWorth: current - explained,
            currentNetWorth: current,
            income: income,
            expense: expense,
            expenseRecovery: recovery,
            fees: fees,
            adjustments: adjustments,
            exchangeImpact: exchangeImpact,
            missingCodes: missing
        )
    }

    private func converted(
        _ amount: Decimal,
        code: String,
        valuation: ValuationService,
        missing: inout Set<String>
    ) -> Decimal? {
        guard let value = valuation.value(amount, currencyCode: code) else {
            missing.insert(code)
            return nil
        }
        return value
    }
}
