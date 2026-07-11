import Foundation

struct ValuationService {
    let baseCurrencyCode: String
    let rates: [ExchangeRate]

    func value(_ amount: Decimal, currencyCode: String) -> Decimal? {
        if currencyCode == baseCurrencyCode { return amount }
        if let direct = rates.first(where: {
            $0.currencyCode == currencyCode && $0.baseCurrencyCode == baseCurrencyCode
        }) {
            return amount * direct.rate
        }
        if let inverse = rates.first(where: {
            $0.currencyCode == baseCurrencyCode && $0.baseCurrencyCode == currencyCode && $0.rate != 0
        }) {
            return amount / inverse.rate
        }
        return nil
    }

    func total(for wallets: [CurrencyWallet]) -> (value: Decimal, missingCodes: Set<String>) {
        var total = Decimal.zero
        var missing = Set<String>()
        for wallet in wallets where wallet.isEnabled {
            if let converted = value(wallet.balance, currencyCode: wallet.currencyCode) {
                total += converted
            } else {
                missing.insert(wallet.currencyCode)
            }
        }
        return (total, missing)
    }
}
