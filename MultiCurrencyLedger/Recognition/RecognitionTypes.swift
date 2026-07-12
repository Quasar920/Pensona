import Foundation

enum RecognizedTransactionType: String, Codable, Equatable {
    case expense, income, transfer, exchange, refund, unknown
}

struct RecognitionConfidenceDTO: Codable, Equatable {
    let type: Double
    let paidAmount: Double
    let currencyCode: Double
    let account: Double
    let category: Double
}

struct RecognitionCandidateDTO: Codable, Equatable {
    let type: RecognizedTransactionType
    let paidAmount: String
    let originalAmount: String?
    let discountAmount: String?
    let feeAmount: String?
    let currencyCode: String
    let date: String
    let time: String
    let merchantOrCounterparty: String?
    let sourceAccountHint: String?
    let destinationAccountHint: String?
    let categoryCandidate: String?
    let note: String?
    let confidence: RecognitionConfidenceDTO
}

struct RecognitionEnvelopeDTO: Codable, Equatable {
    let results: [RecognitionCandidateDTO]
}

struct NormalizedRecognitionCandidate: Equatable {
    let type: RecognizedTransactionType
    let paidAmount: Decimal
    let originalAmount: Decimal?
    let discountAmount: Decimal
    let feeAmount: Decimal
    let currency: SupportedCurrency
    let occurredAt: Date
    let merchantOrCounterparty: String?
    let sourceAccountHint: String?
    let destinationAccountHint: String?
    let categoryCandidate: String?
    let note: String?
    let confidence: RecognitionConfidenceDTO
}

enum RecognitionDecisionReason: String, Error, Equatable {
    case eligible
    case unsupportedType
    case invalidAmount
    case unsupportedCurrency
    case invalidDate
    case futureDate
    case amountNotVisibleInOCR
    case amountRelationshipMismatch
    case riskyStatusText
    case feeRequiresConfirmation
    case accountUnmatched
    case accountAmbiguous
    case currencyWalletMismatch
    case categoryUnmatched
    case lowConfidence
}

enum RecognitionDecision: Equatable {
    case autoEligible(walletID: UUID, candidate: NormalizedRecognitionCandidate)
    case needsConfirmation(reason: RecognitionDecisionReason, candidate: NormalizedRecognitionCandidate?)
    case rejected(reason: RecognitionDecisionReason)
}

enum RecognitionError: LocalizedError, Equatable {
    case invalidResponse
    case emptyResults
    case noRecognizableText

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "识别服务返回了无效数据"
        case .emptyResults: "没有识别到交易记录"
        case .noRecognizableText: "无法读取截图中的交易信息"
        }
    }
}
