import Foundation
import SwiftData

enum TransactionRelationKind: String, CaseIterable, Identifiable {
    case refund
    case reimbursement

    var id: String { rawValue }
    var title: String {
        self == .refund ? AppLocalization.string( "退款") : AppLocalization.string( "报销")
    }
}

@Model
final class TransactionRelation {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var originalTransactionID: UUID
    var relatedTransactionID: UUID
    var amount: Decimal
    /// When one refund/reimbursement exceeds the recoverable balance, the
    /// excess is persisted as a normal "Other Income" transaction. Keeping
    /// its identifier here makes the two system-generated rows auditable and
    /// lets deletion treat them as one operation.
    var excessIncomeTransactionID: UUID?
    var excessIncomeAmount: Decimal?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: TransactionRelationKind,
        originalTransactionID: UUID,
        relatedTransactionID: UUID,
        amount: Decimal,
        excessIncomeTransactionID: UUID? = nil,
        excessIncomeAmount: Decimal? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.originalTransactionID = originalTransactionID
        self.relatedTransactionID = relatedTransactionID
        self.amount = amount
        self.excessIncomeTransactionID = excessIncomeTransactionID
        self.excessIncomeAmount = excessIncomeAmount
        self.createdAt = createdAt
    }

    var kind: TransactionRelationKind {
        TransactionRelationKind(rawValue: kindRawValue) ?? .refund
    }
}
