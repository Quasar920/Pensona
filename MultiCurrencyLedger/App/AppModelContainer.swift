import SwiftData

enum AppModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            LedgerBook.self,
            Account.self,
            CurrencyWallet.self,
            LedgerCategory.self,
            LedgerTransaction.self,
            RecognitionImportRecord.self,
            ExchangeRate.self,
            MonthlyBudget.self
        ])
        return try ModelContainer(for: schema)
    }
}
