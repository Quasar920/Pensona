import Foundation
import SwiftData

enum BulkTransactionError: LocalizedError, Equatable {
    case emptySelection
    case mixedCategoryTypes
    case wrongBookTag

    var errorDescription: String? {
        switch self {
        case .emptySelection: "请至少选择一笔交易"
        case .mixedCategoryTypes: "所选分类与部分交易类型不匹配"
        case .wrongBookTag: "标签与部分交易不属于同一账本"
        }
    }
}

@MainActor
final class BulkTransactionService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func update(
        _ transactions: [LedgerTransaction],
        changesCategory: Bool,
        category: LedgerCategory?,
        changesTags: Bool,
        tags: [TransactionTag],
        changesDate: Bool,
        date: Date
    ) throws {
        guard !transactions.isEmpty else { throw BulkTransactionError.emptySelection }
        if changesCategory, let category {
            let valid = transactions.allSatisfy { transaction in
                (transaction.type == .expense && category.type == .expense)
                    || (transaction.type == .income && category.type == .income)
            }
            guard valid else { throw BulkTransactionError.mixedCategoryTypes }
        }
        if changesTags {
            let valid = transactions.allSatisfy { transaction in
                guard let bookID = transaction.sourceAccount?.book?.id else { return false }
                return tags.allSatisfy { $0.bookID == bookID && !$0.isArchived }
            }
            guard valid else { throw BulkTransactionError.wrongBookTag }
        }

        do {
            for transaction in transactions {
                if changesCategory { transaction.category = category }
                if changesTags { transaction.tags = tags }
                if changesDate { transaction.date = date }
                transaction.updatedAt = .now
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(_ transactions: [LedgerTransaction]) throws {
        guard !transactions.isEmpty else { throw BulkTransactionError.emptySelection }
        try LedgerService(context: context).deleteTransactions(transactions)
    }
}
