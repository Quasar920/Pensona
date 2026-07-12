import AppIntents
import Foundation
import SwiftData

struct RecognizeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "识别并记账"
    static let description = IntentDescription("接收快捷指令识别 API 返回的交易结果并安全入账。")
    static let openAppWhenRun = true

    @Parameter(title: "OCR 文本")
    var ocrText: String

    @Parameter(title: "识别结果 JSON")
    var recognitionJSON: String

    init() {}

    init(ocrText: String, recognitionJSON: String) {
        self.ocrText = ocrText
        self.recognitionJSON = recognitionJSON
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let container = try AppModelContainer.make()
        let context = container.mainContext
        guard let book = try selectedBook(in: context) else {
            throw RecognitionIntentError.missingBook
        }

        let outcomes = try ShortcutRecognitionImportService(context: context).importResults(
            responseJSON: recognitionJSON,
            ocrText: ocrText,
            book: book,
            allowIncomeAutoEntry: UserDefaults.standard.bool(forKey: "recognitionAllowIncomeAutoEntry")
        )
        guard !outcomes.isEmpty else { throw RecognitionError.emptyResults }
        if let recordID = outcomes.compactMap({ outcome -> UUID? in
            if case let .needsConfirmation(recordID) = outcome { return recordID }
            return nil
        }).first {
            UserDefaults.standard.set(recordID.uuidString, forKey: RecognitionPendingRoute.recordIDDefaultsKey)
            return .result(dialog: "请在 App 中确认交易信息")
        }
        if outcomes.contains(where: { if case .duplicate = $0 { return true }; return false }) {
            return .result(dialog: "该交易可能已记录")
        }
        if outcomes.allSatisfy({ if case .autoEntered = $0 { return true }; return false }) {
            return .result(dialog: "已安全入账")
        }
        if case let .rejected(reason) = outcomes[0] {
            throw RecognitionIntentError.rejected(reason)
        }
        throw RecognitionIntentError.rejected(.unsupportedType)
    }

    private func selectedBook(in context: ModelContext) throws -> LedgerBook? {
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        let selectedID = UserDefaults.standard.string(forKey: "selectedBookID")
        return books.first { $0.id.uuidString == selectedID } ?? books.first
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
