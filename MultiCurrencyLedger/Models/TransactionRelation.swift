import Foundation
import SwiftData

enum TransactionRelationKind: String, CaseIterable, Identifiable {
    case refund
    case reimbursement

    var id: String { rawValue }
    var title: String { self == .refund ? "退款" : "报销" }
}

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
        kind: TransactionRelationKind,
        originalTransactionID: UUID,
        relatedTransactionID: UUID,
        amount: Decimal,
        createdAt: Date = .now
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.originalTransactionID = originalTransactionID
        self.relatedTransactionID = relatedTransactionID
        self.amount = amount
        self.createdAt = createdAt
    }

    var kind: TransactionRelationKind {
        TransactionRelationKind(rawValue: kindRawValue) ?? .refund
    }
}
