import Foundation
import SwiftData

enum RecognitionImportStatus: String, Codable, CaseIterable {
    case pendingConfirmation
    case confirmed
    case autoEntered
    case duplicate
    case failed
}

@Model
final class RecognitionImportRecord {
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

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        status: RecognitionImportStatus,
        decisionReason: RecognitionDecisionReason,
        candidateType: RecognizedTransactionType,
        bookID: UUID,
        paidAmount: Decimal,
        currencyCode: String,
        occurredAt: Date,
        merchantOrCounterparty: String? = nil,
        note: String? = nil,
        originalAmount: Decimal? = nil,
        discountAmount: Decimal = 0,
        feeAmount: Decimal = 0,
        sourceAccountHint: String? = nil,
        categoryCandidate: String? = nil,
        selectedWalletID: UUID? = nil,
        selectedCategoryID: UUID? = nil,
        transactionFingerprint: String,
        transactionID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        statusRawValue = status.rawValue
        decisionReasonRawValue = decisionReason.rawValue
        candidateTypeRawValue = candidateType.rawValue
        self.bookID = bookID
        self.paidAmount = paidAmount
        self.currencyCode = currencyCode
        self.occurredAt = occurredAt
        self.merchantOrCounterparty = merchantOrCounterparty
        self.note = note
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.feeAmount = feeAmount
        self.sourceAccountHint = sourceAccountHint
        self.categoryCandidate = categoryCandidate
        self.selectedWalletID = selectedWalletID
        self.selectedCategoryID = selectedCategoryID
        self.transactionFingerprint = transactionFingerprint
        self.transactionID = transactionID
    }

    var status: RecognitionImportStatus {
        RecognitionImportStatus(rawValue: statusRawValue) ?? .failed
    }

    var decisionReason: RecognitionDecisionReason {
        RecognitionDecisionReason(rawValue: decisionReasonRawValue) ?? .unsupportedType
    }
}
