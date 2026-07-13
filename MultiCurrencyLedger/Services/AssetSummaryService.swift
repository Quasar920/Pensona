import Foundation

struct AccountValuationResult {
    let value: Decimal
    let missingCodes: Set<String>
    let hasEnabledWallets: Bool
}

struct AssetSummaryResult {
    let totalAssets: Decimal
    let totalLiabilities: Decimal
    let ownerEquity: Decimal
    let missingCodes: Set<String>
}

struct AssetSummaryService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]

    func value(for account: Account) -> AccountValuationResult {
        // Disabled wallets remain real assets/liabilities; disabling only removes
        // them from future transaction pickers.
        let wallets = account.allWallets
        let result = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .total(for: wallets)

        return AccountValuationResult(
            value: result.value,
            missingCodes: result.missingCodes,
            hasEnabledWallets: !wallets.isEmpty
        )
    }

    func summary(for accounts: [Account]) -> AssetSummaryResult {
        var assetBalances = Decimal.zero
        var totalLiabilities = Decimal.zero
        var missingCodes = Set<String>()

        for account in accounts {
            let accountResult = value(for: account)
            missingCodes.formUnion(accountResult.missingCodes)

            if accountResult.value >= 0 {
                // A positive balance is an asset. For credit and payable accounts,
                // this represents an overpayment rather than an amount owed.
                assetBalances += accountResult.value
            } else {
                // Negative balances are represented as a positive liability total.
                totalLiabilities += -accountResult.value
            }
        }

        let ownerEquity = assetBalances - totalLiabilities
        let totalAssets = totalLiabilities + ownerEquity

        return AssetSummaryResult(
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            ownerEquity: ownerEquity,
            missingCodes: missingCodes
        )
    }
}
