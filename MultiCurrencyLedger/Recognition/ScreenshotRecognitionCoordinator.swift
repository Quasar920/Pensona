import CoreGraphics
import Foundation

struct RecognitionRemoteAccountOption: Codable, Equatable {
    let accountName: String
    let currencyCode: String
}

struct RecognitionRemoteCategoryOption: Codable, Equatable {
    let name: String
    let type: CategoryKind
}

struct RecognitionRemoteContext: Codable, Equatable {
    let accounts: [RecognitionRemoteAccountOption]
    let categories: [RecognitionRemoteCategoryOption]

    init(localContext: RecognitionRequestContext) {
        var uniqueAccounts: [String: RecognitionRemoteAccountOption] = [:]
        for account in localContext.accounts {
            let remote = RecognitionRemoteAccountOption(
                accountName: account.accountName, currencyCode: account.currencyCode
            )
            uniqueAccounts["\(remote.accountName)\u{0}\(remote.currencyCode)"] = remote
        }
        accounts = uniqueAccounts.values.sorted {
            ($0.accountName, $0.currencyCode) < ($1.accountName, $1.currencyCode)
        }

        var uniqueCategories: [String: RecognitionRemoteCategoryOption] = [:]
        for category in localContext.categories {
            let remote = RecognitionRemoteCategoryOption(name: category.name, type: category.type)
            uniqueCategories["\(remote.type.rawValue)\u{0}\(remote.name)"] = remote
        }
        categories = uniqueCategories.values.sorted {
            ($0.type.rawValue, $0.name) < ($1.type.rawValue, $1.name)
        }
    }
}

struct RecognitionAPIRequest: Codable, Equatable {
    let ocrText: String
    let context: RecognitionRemoteContext
    let requestedAt: Date
}

protocol RecognitionAPIClient: AnyObject {
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data
}

struct RecognitionBatchAnalysis: Equatable {
    let document: OCRDocument
    let decisions: [RecognitionDecision]
}

@MainActor
struct ScreenshotRecognitionCoordinator {
    let ocr: ScreenshotOCRServicing
    let apiClient: RecognitionAPIClient
    var parser = RecognitionResponseParser()
    var contextBuilder = RecognitionContextBuilder()
    var evaluator = RecognitionSafetyEvaluator()

    func analyze(
        image: CGImage,
        book: LedgerBook,
        categories: [LedgerCategory],
        allowIncomeAutoEntry: Bool,
        now: Date = .now
    ) async throws -> RecognitionBatchAnalysis {
        try Task.checkCancellation()
        let document = try await ocr.recognizeText(in: image)
        try Task.checkCancellation()
        let localContext = contextBuilder.makeContext(book: book, categories: categories)
        let request = RecognitionAPIRequest(
            ocrText: document.fullText,
            context: RecognitionRemoteContext(localContext: localContext),
            requestedAt: now
        )
        try Task.checkCancellation()
        let data = try await apiClient.recognize(request)
        try Task.checkCancellation()
        let envelope = try parser.parse(data)
        var analysisEvaluator = evaluator
        analysisEvaluator.now = { now }
        var decisions = envelope.results.map {
            analysisEvaluator.evaluate(
                $0, ocrText: document.fullText, context: localContext,
                allowIncomeAutoEntry: allowIncomeAutoEntry
            )
        }
        if decisions.count > 1 {
            decisions = decisions.map { decision in
                guard case let .autoEligible(_, candidate) = decision else { return decision }
                return .needsConfirmation(reason: .multipleCandidates, candidate: candidate)
            }
        }
        return RecognitionBatchAnalysis(document: document, decisions: decisions)
    }
}
