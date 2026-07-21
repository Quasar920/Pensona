import Foundation
import SwiftData

@MainActor
final class LedgerBookService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createBook(name: String) throws -> LedgerBook {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("请输入账本名称") }

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard !books.contains(where: {
            $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw ValidationError("已有同名账本")
        }

        let nextOrder = (books.map(\.sortOrder).max() ?? -1) + 1
        let book = LedgerBook(name: cleanName, sortOrder: nextOrder)
        context.insert(book)
        try context.save()
        return book
    }

    func rename(_ book: LedgerBook, to name: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("请输入账本名称") }

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard !books.contains(where: {
            $0.id != book.id
                && $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw ValidationError("已有同名账本")
        }

        book.name = cleanName
        book.updatedAt = .now
        try context.save()
    }

    func delete(_ book: LedgerBook) throws {
        let bookID = book.id
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard books.count > 1 else { throw LedgerError.bookInUse }

        let hasTransactions = try context.fetchCount(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasBudgets = try context.fetchCount(FetchDescriptor<MonthlyBudget>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasTemplates = try context.fetchCount(FetchDescriptor<TransactionTemplate>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasRecurringSchedules = try context.fetchCount(FetchDescriptor<RecurringSchedule>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasInstallmentPlans = try context.fetchCount(FetchDescriptor<InstallmentPlan>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasRecognitionRecords = try context.fetchCount(FetchDescriptor<RecognitionImportRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasImportBatches = try context.fetchCount(FetchDescriptor<TransactionImportBatch>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasSavingsGoals = try context.fetchCount(FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasAttachments = try context.fetchCount(FetchDescriptor<TransactionAttachment>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasTags = try context.fetchCount(FetchDescriptor<TransactionTag>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0
        let hasCompatibilityCategories = try context.fetchCount(FetchDescriptor<LedgerCategory>(
            predicate: #Predicate { $0.bookID == bookID }
        )) > 0

        guard ![
            hasTransactions, hasBudgets, hasTemplates, hasRecurringSchedules,
            hasInstallmentPlans, hasRecognitionRecords, hasImportBatches,
            hasSavingsGoals, hasAttachments, hasTags, hasCompatibilityCategories
        ].contains(true) else {
            throw LedgerError.bookInUse
        }

        context.delete(book)
        try context.save()
    }
}
