import Foundation
import SwiftData

/// Exact schema used before the feature-completion work. Keeping these model
/// definitions lets SwiftData recognize an existing unversioned 1.0 store.
enum LedgerSchemaLegacy: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self
        ]
    }

    @Model final class LedgerBook {
        @Attribute(.unique) var id: UUID
        var name: String
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \Account.book) var accounts: [Account]

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id; self.name = name; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt; accounts = []
        }
    }

    @Model final class Account {
        @Attribute(.unique) var id: UUID
        var name: String
        var typeRawValue: String
        var note: String?
        var isHidden: Bool
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        var book: LedgerBook?
        @Relationship(deleteRule: .cascade, inverse: \CurrencyWallet.account) var wallets: [CurrencyWallet]

        init(id: UUID = UUID(), name: String, typeRawValue: String, note: String? = nil,
             book: LedgerBook? = nil, isHidden: Bool = false, sortOrder: Int = 0,
             createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id; self.name = name; self.typeRawValue = typeRawValue; self.note = note
            self.book = book; self.isHidden = isHidden; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt; wallets = []
        }
    }

    @Model final class CurrencyWallet {
        @Attribute(.unique) var id: UUID
        var currencyCode: String
        var balance: Decimal
        var isEnabled: Bool
        var createdAt: Date
        var updatedAt: Date
        var account: Account?

        init(id: UUID = UUID(), currencyCode: String, balance: Decimal = 0, isEnabled: Bool = true,
             account: Account? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id; self.currencyCode = currencyCode; self.balance = balance
            self.isEnabled = isEnabled; self.account = account
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model final class LedgerCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var typeRawValue: String
        var symbolName: String
        var sortOrder: Int
        var isSystem: Bool

        init(id: UUID = UUID(), name: String, typeRawValue: String, symbolName: String,
             sortOrder: Int, isSystem: Bool = false) {
            self.id = id; self.name = name; self.typeRawValue = typeRawValue
            self.symbolName = symbolName; self.sortOrder = sortOrder; self.isSystem = isSystem
        }
    }

    @Model final class LedgerTransaction {
        @Attribute(.unique) var id: UUID
        var typeRawValue: String
        var amount: Decimal?
        var currencyCode: String?
        var date: Date
        var note: String?
        var createdAt: Date
        var updatedAt: Date
        var sourceAmount: Decimal?
        var sourceCurrencyCode: String?
        var destinationAmount: Decimal?
        var destinationCurrencyCode: String?
        var feeAmount: Decimal?
        var feeCurrencyCode: String?
        var exchangeRate: Decimal?
        var adjustmentDirectionRawValue: String?
        var adjustmentReason: String?
        var merchantOrCounterparty: String?
        var originalAmount: Decimal?
        var discountAmount: Decimal?
        var recognitionImportID: UUID?
        @Relationship(deleteRule: .nullify) var sourceAccount: Account?
        @Relationship(deleteRule: .nullify) var sourceWallet: CurrencyWallet?
        @Relationship(deleteRule: .nullify) var destinationAccount: Account?
        @Relationship(deleteRule: .nullify) var destinationWallet: CurrencyWallet?
        @Relationship(deleteRule: .nullify) var feeWallet: CurrencyWallet?
        @Relationship(deleteRule: .nullify) var category: LedgerCategory?

        init(id: UUID = UUID(), typeRawValue: String, date: Date = .now,
             createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id; self.typeRawValue = typeRawValue; self.date = date
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model final class RecognitionImportRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var statusRawValue: String
        var decisionReasonRawValue: String
        var candidateTypeRawValue: String
        var bookID: UUID
        var paidAmount: Decimal
        var currencyCode: String
        var occurredAt: Date
        var merchantOrCounterparty: String?
        var note: String?
        var originalAmount: Decimal?
        var discountAmount: Decimal
        var feeAmount: Decimal
        var sourceAccountHint: String?
        var categoryCandidate: String?
        var selectedWalletID: UUID?
        var selectedCategoryID: UUID?
        var transactionFingerprint: String
        var transactionID: UUID?

        init(id: UUID = UUID(), createdAt: Date = .now, statusRawValue: String,
             decisionReasonRawValue: String, candidateTypeRawValue: String, bookID: UUID,
             paidAmount: Decimal, currencyCode: String, occurredAt: Date,
             discountAmount: Decimal = 0, feeAmount: Decimal = 0,
             transactionFingerprint: String) {
            self.id = id; self.createdAt = createdAt; self.statusRawValue = statusRawValue
            self.decisionReasonRawValue = decisionReasonRawValue; self.candidateTypeRawValue = candidateTypeRawValue
            self.bookID = bookID; self.paidAmount = paidAmount; self.currencyCode = currencyCode
            self.occurredAt = occurredAt; self.discountAmount = discountAmount
            self.feeAmount = feeAmount; self.transactionFingerprint = transactionFingerprint
        }
    }

    @Model final class ExchangeRate {
        @Attribute(.unique) var id: UUID
        var currencyCode: String
        var baseCurrencyCode: String
        var rate: Decimal
        var sourceRawValue: String
        var updatedAt: Date

        init(id: UUID = UUID(), currencyCode: String, baseCurrencyCode: String, rate: Decimal,
             sourceRawValue: String, updatedAt: Date = .now) {
            self.id = id; self.currencyCode = currencyCode; self.baseCurrencyCode = baseCurrencyCode
            self.rate = rate; self.sourceRawValue = sourceRawValue; self.updatedAt = updatedAt
        }
    }

    @Model final class MonthlyBudget {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var scopeKey: String
        var bookID: UUID
        var monthStart: Date
        var currencyCode: String
        var amount: Decimal
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), scopeKey: String, bookID: UUID, monthStart: Date,
             currencyCode: String, amount: Decimal, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id; self.scopeKey = scopeKey; self.bookID = bookID; self.monthStart = monthStart
            self.currencyCode = currencyCode; self.amount = amount
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
}

enum LedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

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

enum LedgerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            AASplit.self, AASettlement.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            CloudSyncTombstone.self, CloudSyncConflictCopy.self
        ]
    }
}

enum LedgerSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    /// The V3 relation is intentionally frozen here. The live
    /// `TransactionRelation` gained the excess-income fields in V4; reusing
    /// it in both schema versions gives SwiftData two identical checksums and
    /// crashes before the model container can open.
    @Model
    final class TransactionRelation {
        @Attribute(.unique) var id: UUID
        var kindRawValue: String
        var originalTransactionID: UUID
        var relatedTransactionID: UUID
        var amount: Decimal
        var createdAt: Date

        init(
            id: UUID = UUID(),
            kindRawValue: String,
            originalTransactionID: UUID,
            relatedTransactionID: UUID,
            amount: Decimal,
            createdAt: Date = .now
        ) {
            self.id = id
            self.kindRawValue = kindRawValue
            self.originalTransactionID = originalTransactionID
            self.relatedTransactionID = relatedTransactionID
            self.amount = amount
            self.createdAt = createdAt
        }
    }

    static var models: [any PersistentModel.Type] {
        [
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            AASplit.self, AASettlement.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self, RepaymentReminder.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            CloudSyncTombstone.self, CloudSyncConflictCopy.self
        ]
    }
}

enum LedgerSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            AASplit.self, AASettlement.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self, RepaymentReminder.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            CloudSyncTombstone.self, CloudSyncConflictCopy.self
        ]
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            LedgerSchemaLegacy.self, LedgerSchemaV1.self, LedgerSchemaV2.self,
            LedgerSchemaV3.self, LedgerSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LedgerSchemaLegacy.self, toVersion: LedgerSchemaV1.self),
            .lightweight(fromVersion: LedgerSchemaV1.self, toVersion: LedgerSchemaV2.self),
            .lightweight(fromVersion: LedgerSchemaV2.self, toVersion: LedgerSchemaV3.self),
            .lightweight(fromVersion: LedgerSchemaV3.self, toVersion: LedgerSchemaV4.self)
        ]
    }
}
