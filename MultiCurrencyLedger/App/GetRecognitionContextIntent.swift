import AppIntents
import Foundation
import SwiftData

struct GetRecognitionContextIntent: AppIntent {
    static let title: LocalizedStringResource = "获取记账识别候选"
    static let description = IntentDescription("输出当前账本的账户、币种钱包与分类候选，供快捷指令的识别 API 使用。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let container = try AppModelContainer.make()
        let context = container.mainContext
        guard let book = try selectedBook(in: context) else {
            throw RecognitionIntentError.missingBook
        }
        let json = try ShortcutRecognitionContextService(context: context).exportJSON(for: book)
        return .result(value: json, dialog: "已提供当前账本的识别候选")
    }

    private func selectedBook(in context: ModelContext) throws -> LedgerBook? {
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        let selectedID = UserDefaults.standard.string(forKey: "selectedBookID")
        return books.first { $0.id.uuidString == selectedID } ?? books.first
    }
}
