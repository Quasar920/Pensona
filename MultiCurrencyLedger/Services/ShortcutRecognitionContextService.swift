import Foundation
import SwiftData

@MainActor
final class ShortcutRecognitionContextService {
    private let context: ModelContext
    private var builder = RecognitionContextBuilder()

    init(context: ModelContext) {
        self.context = context
    }

    func exportJSON(for book: LedgerBook) throws -> String {
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let recognitionContext = builder.makeContext(book: book, categories: categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = String(data: try encoder.encode(recognitionContext), encoding: .utf8) else {
            throw RecognitionContextExportError.encodingFailed
        }
        return json
    }
}

enum RecognitionContextExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { "无法生成识别候选" }
}
