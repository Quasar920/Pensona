import SwiftData

enum LedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            CloudSyncTombstone.self, CloudSyncConflictCopy.self
        ]
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
