import Foundation
import SwiftData

enum RecognitionWorkflowOutcome: Equatable {
    case autoEntered(transactionID: UUID)
    case needsConfirmation(recordID: UUID)
    case duplicate(recordID: UUID)
    case rejected(reason: RecognitionDecisionReason)
}

/// Converts a local recognition decision into the only two permitted state
/// changes: a transaction created through `LedgerService`, or a sanitized
/// pending-confirmation record. It is intentionally unaware of screenshots and
/// OCR text.
@MainActor
final class RecognitionWorkflowService {
    private let context: ModelContext
    private let duplicateDetector: RecognitionDuplicateDetector

    init(
        context: ModelContext,
        duplicateDetector: RecognitionDuplicateDetector = RecognitionDuplicateDetector()
    ) {
        self.context = context
        self.duplicateDetector = duplicateDetector
    }

    func apply(_ decision: RecognitionDecision, in book: LedgerBook) throws -> RecognitionWorkflowOutcome {
        guard let draft = decision.confirmationDraft else {
            if case let .rejected(reason) = decision { return .rejected(reason: reason) }
            return .rejected(reason: .unsupportedType)
        }
        let records = try context.fetch(FetchDescriptor<RecognitionImportRecord>())
        if let existing = duplicateDetector.existingRecord(for: draft, records: records) {
            return .duplicate(recordID: existing.id)
        }

        switch decision {
        case let .autoEligible(walletID, candidate):
            guard let wallet = wallets(in: book).first(where: { $0.id == walletID }),
                  let category = matchingCategory(for: candidate) else {
                return try persistPending(draft: draft, decision: decision, book: book)
            }
            let transaction = try RecognitionEntryService(context: context).confirm(
                draft,
                wallet: wallet,
                category: category,
                importStatus: .autoEntered
            )
            return .autoEntered(transactionID: transaction.id)

        case .needsConfirmation:
            return try persistPending(draft: draft, decision: decision, book: book)

        case let .rejected(reason):
            return .rejected(reason: reason)
        }
    }

    private func persistPending(
        draft: RecognitionConfirmationDraft,
        decision: RecognitionDecision,
        book: LedgerBook
    ) throws -> RecognitionWorkflowOutcome {
        let hints = candidateHints(from: decision)
        let record = RecognitionImportRecordFactory.make(
            draft: draft,
            status: .pendingConfirmation,
            bookID: book.id,
            sourceAccountHint: hints.sourceAccountHint,
            categoryCandidate: hints.categoryCandidate
        )
        context.insert(record)
        try context.save()
        return .needsConfirmation(recordID: record.id)
    }

    private func wallets(in book: LedgerBook) -> [CurrencyWallet] {
        book.accounts.filter { !$0.isArchived }.flatMap(\.enabledWallets)
    }

    private func matchingCategory(for candidate: NormalizedRecognitionCandidate) -> LedgerCategory? {
        let expected: CategoryKind = candidate.type == .income ? .income : .expense
        let descriptor = FetchDescriptor<LedgerCategory>()
        return try? context.fetch(descriptor).first {
            $0.name == candidate.categoryCandidate && $0.type == expected
        }
    }

    private func candidateHints(
        from decision: RecognitionDecision
    ) -> (sourceAccountHint: String?, categoryCandidate: String?) {
        switch decision {
        case let .autoEligible(_, candidate), let .needsConfirmation(_, candidate?):
            return (candidate.sourceAccountHint, candidate.categoryCandidate)
        case .needsConfirmation(_, nil), .rejected:
            return (nil, nil)
        }
    }
}
