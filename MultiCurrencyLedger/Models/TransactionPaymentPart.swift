import Foundation
import SwiftData

@Model
final class TransactionPaymentPart {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var sortOrder: Int
    var createdAt: Date
    var transaction: LedgerTransaction?
    @Relationship(deleteRule: .nullify) var wallet: CurrencyWallet?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        sortOrder: Int,
        transaction: LedgerTransaction? = nil,
        wallet: CurrencyWallet?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.sortOrder = sortOrder
        self.transaction = transaction
        self.wallet = wallet
        self.createdAt = createdAt
    }
}

struct TransactionPaymentPartDraft {
    var wallet: CurrencyWallet
    var amount: Decimal
}
