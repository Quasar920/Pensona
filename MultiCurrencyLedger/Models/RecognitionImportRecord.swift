import Foundation
import SwiftData

enum RecognitionImportStatus: String, Codable, CaseIterable {
    case confirmed
}

@Model
final class RecognitionImportRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var statusRawValue: String
    var decisionReasonRawValue: String
    var candidateTypeRawValue: String
    var paidAmount: Decimal
    var currencyCode: String
    var transactionID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        status: RecognitionImportStatus,
        decisionReason: RecognitionDecisionReason,
        candidateType: RecognizedTransactionType,
        paidAmount: Decimal,
        currencyCode: String,
        transactionID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        statusRawValue = status.rawValue
        decisionReasonRawValue = decisionReason.rawValue
        candidateTypeRawValue = candidateType.rawValue
        self.paidAmount = paidAmount
        self.currencyCode = currencyCode
        self.transactionID = transactionID
    }

    var status: RecognitionImportStatus {
        RecognitionImportStatus(rawValue: statusRawValue) ?? .confirmed
    }

    var decisionReason: RecognitionDecisionReason {
        RecognitionDecisionReason(rawValue: decisionReasonRawValue) ?? .unsupportedType
    }
}
