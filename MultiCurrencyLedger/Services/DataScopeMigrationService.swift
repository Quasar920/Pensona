import Foundation
import SwiftData

struct DataScopeMigrationResult: Equatable {
    let defaultBookID: UUID
    let backfilledTransactionCount: Int
    let crossBookTransferCount: Int
    let globalizedSystemCategoryCount: Int
    let globalizedSavingsGoalCount: Int
    let didRun: Bool
}

@MainActor
final class DataScopeMigrationService {
    static let completionKey = "dataScopeMigration.v3.completed"
    static let crossBookDiagnosticKey = "dataScopeMigration.v3.crossBookTransferCount"

    private let context: ModelContext
    private let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    func migrateIfNeeded() throws -> DataScopeMigrationResult {
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
            }
        if defaults.bool(forKey: Self.completionKey), let defaultBook = books.first {
            return DataScopeMigrationResult(
                defaultBookID: defaultBook.id,
                backfilledTransactionCount: 0,
                crossBookTransferCount: defaults.integer(forKey: Self.crossBookDiagnosticKey),
                globalizedSystemCategoryCount: 0,
                globalizedSavingsGoalCount: 0,
                didRun: false
            )
        }

        let defaultBook: LedgerBook
        if let first = books.first {
            defaultBook = first
        } else {
            defaultBook = LedgerBook(name: "日常账本")
            context.insert(defaultBook)
        }

        var backfilledCount = 0
        var crossBookCount = 0
        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>())
        where transaction.bookID == nil {
            let sourceBookID = transaction.sourceAccount?.book?.id
                ?? transaction.sourceWallet?.account?.book?.id
            let destinationBookID = transaction.destinationAccount?.book?.id
                ?? transaction.destinationWallet?.account?.book?.id
            if transaction.type == .transfer,
               let sourceBookID,
               let destinationBookID,
               sourceBookID != destinationBookID {
                crossBookCount += 1
            }
            transaction.bookID = sourceBookID ?? destinationBookID ?? defaultBook.id
            transaction.updatedAt = .now
            backfilledCount += 1
        }

        var globalizedCategoryCount = 0
        for category in try context.fetch(FetchDescriptor<LedgerCategory>())
        where category.isSystem && category.bookID != nil {
            category.bookID = nil
            category.updatedAt = .now
            globalizedCategoryCount += 1
        }

        var globalizedGoalCount = 0
        for goal in try context.fetch(FetchDescriptor<SavingsGoal>()) where !goal.isGloballyVisible {
            goal.isGloballyVisible = true
            goal.updatedAt = .now
            globalizedGoalCount += 1
        }

        do {
            try context.save()
            defaults.set(crossBookCount, forKey: Self.crossBookDiagnosticKey)
            defaults.set(true, forKey: Self.completionKey)
        } catch {
            context.rollback()
            throw error
        }

        return DataScopeMigrationResult(
            defaultBookID: defaultBook.id,
            backfilledTransactionCount: backfilledCount,
            crossBookTransferCount: crossBookCount,
            globalizedSystemCategoryCount: globalizedCategoryCount,
            globalizedSavingsGoalCount: globalizedGoalCount,
            didRun: true
        )
    }
}
