import SwiftData

@MainActor
enum InitialDataService {
    static func seedIfNeeded(context: ModelContext) throws {
        try DefaultCategoryCatalog.upgrade(context: context)

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        if books.isEmpty {
            context.insert(LedgerBook(name: AppLocalization.string("日常账本")))
        }
        try context.save()
    }
}
