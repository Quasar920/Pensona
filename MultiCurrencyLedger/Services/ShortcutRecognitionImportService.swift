import Foundation
import SwiftData

/// The app-side boundary for a Shortcut-owned recognition flow. The Shortcut
/// owns capture, OCR, API URL, credentials, and network transport; this service
/// only validates the returned JSON against local ledger data before writing.
@MainActor
final class ShortcutRecognitionImportService {
    private let context: ModelContext
    private var parser = RecognitionResponseParser()
    private var contextBuilder = RecognitionContextBuilder()
    private var evaluator = RecognitionSafetyEvaluator()

    init(context: ModelContext) {
        self.context = context
    }

    func importResults(
        responseJSON: String,
        ocrText: String,
        book: LedgerBook,
        allowIncomeAutoEntry: Bool,
        now: Date = .now
    ) throws -> [RecognitionWorkflowOutcome] {
        let envelope = try parser.parse(Data(responseJSON.utf8))
        let localContext = contextBuilder.makeContext(
            book: book,
            accounts: try context.fetch(FetchDescriptor<Account>()),
            categories: try context.fetch(FetchDescriptor<LedgerCategory>())
        )
        evaluator.now = { now }
        var decisions = envelope.results.map {
            evaluator.evaluate(
                $0,
                ocrText: ocrText,
                context: localContext,
                allowIncomeAutoEntry: allowIncomeAutoEntry
            )
        }
        if decisions.count > 1 {
            decisions = decisions.map { decision in
                guard case let .autoEligible(_, candidate) = decision else { return decision }
                return .needsConfirmation(reason: .multipleCandidates, candidate: candidate)
            }
        }
        return try decisions.map { try RecognitionWorkflowService(context: context).apply($0, in: book) }
    }
}
