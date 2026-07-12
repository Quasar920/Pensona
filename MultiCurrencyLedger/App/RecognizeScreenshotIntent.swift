import AppIntents
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

struct RecognizeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "识别并记账"
    static let description = IntentDescription("识别支付截图，并在安全时自动入账。")
    static let openAppWhenRun = true

    @Parameter(title: "截图", supportedTypeIdentifiers: ["public.image"])
    var screenshot: IntentFile

    init() {}

    init(screenshot: IntentFile) {
        self.screenshot = screenshot
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let data = screenshot.data
        guard let image = Self.makeCGImage(data) else { throw RecognitionError.noRecognizableText }
        let container = try AppModelContainer.make()
        let context = container.mainContext
        guard let book = try selectedBook(in: context) else {
            throw RecognitionIntentError.missingBook
        }

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let coordinator = ScreenshotRecognitionCoordinator(
            ocr: VisionScreenshotOCRService(),
            apiClient: try RecognitionRuntimeConfiguration.makeHTTPClient()
        )
        let analysis = try await coordinator.analyze(
            image: image,
            book: book,
            categories: categories,
            allowIncomeAutoEntry: UserDefaults.standard.bool(forKey: "recognitionAllowIncomeAutoEntry")
        )
        guard analysis.decisions.count == 1, let decision = analysis.decisions.first else {
            throw RecognitionError.emptyResults
        }
        let outcome = try RecognitionWorkflowService(context: context).apply(decision, in: book)
        switch outcome {
        case .autoEntered:
            return .result(dialog: "已安全入账")
        case let .needsConfirmation(recordID):
            UserDefaults.standard.set(recordID.uuidString, forKey: RecognitionPendingRoute.recordIDDefaultsKey)
            return .result(dialog: "请在 App 中确认交易信息")
        case .duplicate:
            return .result(dialog: "该交易可能已记录")
        case let .rejected(reason):
            throw RecognitionIntentError.rejected(reason)
        }
    }

    private func selectedBook(in context: ModelContext) throws -> LedgerBook? {
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        let selectedID = UserDefaults.standard.string(forKey: "selectedBookID")
        return books.first { $0.id.uuidString == selectedID } ?? books.first
    }

    private static func makeCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

enum RecognitionPendingRoute {
    static let recordIDDefaultsKey = "pendingRecognitionImportRecordID"
}

enum RecognitionIntentError: LocalizedError {
    case missingBook
    case rejected(RecognitionDecisionReason)

    var errorDescription: String? {
        switch self {
        case .missingBook: "请先创建账本和账户"
        case let .rejected(reason): "无法安全识别这笔交易：\(reason.rawValue)"
        }
    }
}
