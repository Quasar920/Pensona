import SwiftData

enum AppModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            LedgerBook.self,
            Account.self,
            CurrencyWallet.self,
            LedgerCategory.self,
            LedgerTransaction.self,
            TransactionTag.self,
            TransactionAttachment.self,
            TransactionTemplate.self,
            TransactionPaymentPart.self,
            TransactionRelation.self,
            RecurringSchedule.self,
            RecurringOccurrence.self,
            InstallmentPlan.self,
            InstallmentOccurrence.self,
            RecognitionImportRecord.self,
            ExchangeRate.self,
            MonthlyBudget.self,
            SavingsGoal.self,
            SavingsAllocation.self,
            TransactionImportBatch.self,
            TransactionImportFingerprint.self,
            CloudSyncTombstone.self,
            CloudSyncConflictCopy.self
        ])
        return try ModelContainer(for: schema)
    }
}
