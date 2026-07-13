import Foundation
import SwiftData

@Model
final class TransactionTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookID: UUID
    var typeRawValue: String
    var amount: Decimal
    var sourceWalletID: UUID
    var destinationWalletID: UUID?
    var destinationAmount: Decimal?
    var feeAmount: Decimal?
    var feeWalletID: UUID?
    var categoryID: UUID?
    var tagIDsData: Data
    var paymentPartsData: Data
    var note: String?
    var merchantOrCounterparty: String?
    var adjustmentDirectionRawValue: String?
    var adjustmentReason: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        bookID: UUID,
        type: TransactionKind,
        amount: Decimal,
        sourceWalletID: UUID,
        destinationWalletID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        feeAmount: Decimal? = nil,
        feeWalletID: UUID? = nil,
        categoryID: UUID? = nil,
        tagIDs: [UUID] = [],
        paymentParts: [TemplatePaymentPartReference] = [],
        note: String? = nil,
        merchantOrCounterparty: String? = nil,
        adjustmentDirection: AdjustmentDirection? = nil,
        adjustmentReason: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.bookID = bookID
        typeRawValue = type.rawValue
        self.amount = amount
        self.sourceWalletID = sourceWalletID
        self.destinationWalletID = destinationWalletID
        self.destinationAmount = destinationAmount
        self.feeAmount = feeAmount
        self.feeWalletID = feeWalletID
        self.categoryID = categoryID
        tagIDsData = (try? JSONEncoder().encode(tagIDs)) ?? Data()
        paymentPartsData = (try? JSONEncoder().encode(paymentParts)) ?? Data()
        self.note = note
        self.merchantOrCounterparty = merchantOrCounterparty
        adjustmentDirectionRawValue = adjustmentDirection?.rawValue
        self.adjustmentReason = adjustmentReason
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: TransactionKind {
        TransactionKind(rawValue: typeRawValue) ?? .expense
    }

    var adjustmentDirection: AdjustmentDirection? {
        adjustmentDirectionRawValue.flatMap(AdjustmentDirection.init(rawValue:))
    }

    var tagIDs: [UUID] {
        (try? JSONDecoder().decode([UUID].self, from: tagIDsData)) ?? []
    }

    var paymentPartReferences: [TemplatePaymentPartReference] {
        (try? JSONDecoder().decode([TemplatePaymentPartReference].self, from: paymentPartsData)) ?? []
    }
}

struct TemplatePaymentPartReference: Codable, Equatable {
    let walletID: UUID
    let amount: Decimal
}
