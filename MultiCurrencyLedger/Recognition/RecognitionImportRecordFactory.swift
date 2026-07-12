import CryptoKit
import Foundation

struct RecognitionImportRecordFactory {
    static func make(
        draft: RecognitionConfirmationDraft,
        status: RecognitionImportStatus,
        bookID: UUID,
        sourceAccountHint: String? = nil,
        categoryCandidate: String? = nil,
        selectedWalletID: UUID? = nil,
        selectedCategoryID: UUID? = nil
    ) -> RecognitionImportRecord {
        RecognitionImportRecord(
            status: status,
            decisionReason: draft.decisionReason,
            candidateType: draft.type,
            bookID: bookID,
            paidAmount: draft.paidAmount,
            currencyCode: draft.currency.rawValue,
            occurredAt: draft.occurredAt,
            merchantOrCounterparty: draft.merchantForPersistence,
            note: draft.noteForPersistence,
            originalAmount: draft.originalAmount,
            discountAmount: draft.discountAmount,
            feeAmount: draft.feeAmount,
            sourceAccountHint: sourceAccountHint,
            categoryCandidate: categoryCandidate,
            selectedWalletID: selectedWalletID,
            selectedCategoryID: selectedCategoryID,
            transactionFingerprint: RecognitionTransactionFingerprint.make(for: draft)
        )
    }
}

enum RecognitionTransactionFingerprint {
    static func make(for draft: RecognitionConfirmationDraft) -> String {
        let merchant = draft.merchantForPersistence?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) ?? ""
        let amount = NSDecimalNumber(decimal: draft.paidAmount).stringValue
        let minute = Int(draft.occurredAt.timeIntervalSince1970 / 60)
        let payload = [draft.type.rawValue, amount, draft.currency.rawValue, String(minute), merchant]
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct RecognitionDuplicateDetector {
    func existingRecord(
        for draft: RecognitionConfirmationDraft,
        records: [RecognitionImportRecord]
    ) -> RecognitionImportRecord? {
        let fingerprint = RecognitionTransactionFingerprint.make(for: draft)
        return records.first { $0.transactionFingerprint == fingerprint }
    }
}
