import Foundation

struct RecognitionConfirmationDraft: Equatable {
    var type: RecognizedTransactionType
    var paidAmount: Decimal
    var currency: SupportedCurrency
    var occurredAt: Date
    var merchantOrCounterparty: String
    var note: String
    var originalAmount: Decimal?
    var discountAmount: Decimal
    var feeAmount: Decimal
    let decisionReason: RecognitionDecisionReason

    init(
        type: RecognizedTransactionType,
        paidAmount: Decimal,
        currency: SupportedCurrency,
        occurredAt: Date,
        merchantOrCounterparty: String,
        note: String,
        originalAmount: Decimal?,
        discountAmount: Decimal,
        feeAmount: Decimal,
        decisionReason: RecognitionDecisionReason
    ) {
        self.type = type
        self.paidAmount = paidAmount
        self.currency = currency
        self.occurredAt = occurredAt
        self.merchantOrCounterparty = merchantOrCounterparty
        self.note = note
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.feeAmount = feeAmount
        self.decisionReason = decisionReason
    }

    init(candidate: NormalizedRecognitionCandidate, decisionReason: RecognitionDecisionReason) {
        type = candidate.type
        paidAmount = candidate.paidAmount
        currency = candidate.currency
        occurredAt = candidate.occurredAt
        merchantOrCounterparty = candidate.merchantOrCounterparty ?? ""
        note = candidate.note ?? ""
        originalAmount = candidate.originalAmount
        discountAmount = candidate.discountAmount
        feeAmount = candidate.feeAmount
        self.decisionReason = decisionReason
    }

    var isSupportedForConfirmation: Bool {
        (type == .expense || type == .income) && feeAmount == 0
    }

    var noteForPersistence: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var merchantForPersistence: String? {
        let trimmed = merchantOrCounterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension RecognitionDecision {
    var confirmationDraft: RecognitionConfirmationDraft? {
        switch self {
        case let .autoEligible(_, candidate):
            RecognitionConfirmationDraft(candidate: candidate, decisionReason: .eligible)
        case let .needsConfirmation(reason, candidate?):
            RecognitionConfirmationDraft(candidate: candidate, decisionReason: reason)
        case .needsConfirmation(_, nil), .rejected:
            nil
        }
    }
}

extension RecognitionImportRecord {
    var confirmationDraft: RecognitionConfirmationDraft? {
        guard let type = RecognizedTransactionType(rawValue: candidateTypeRawValue),
              let currency = SupportedCurrency(rawValue: currencyCode) else {
            return nil
        }
        return RecognitionConfirmationDraft(
            type: type,
            paidAmount: paidAmount,
            currency: currency,
            occurredAt: occurredAt,
            merchantOrCounterparty: merchantOrCounterparty ?? "",
            note: note ?? "",
            originalAmount: originalAmount,
            discountAmount: discountAmount,
            feeAmount: feeAmount,
            decisionReason: decisionReason
        )
    }
}
