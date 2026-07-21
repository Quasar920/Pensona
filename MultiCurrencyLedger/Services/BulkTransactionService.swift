import Foundation
import SwiftData

enum BulkTransactionError: LocalizedError, Equatable {
    case emptySelection
    case mixedCategoryTypes

    var errorDescription: String? {
        switch self {
        case .emptySelection: AppLocalization.string( "请至少选择一笔交易")
        case .mixedCategoryTypes: AppLocalization.string( "所选分类与部分交易类型不匹配")
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
        changesDate: Bool,
        date: Date
    ) throws {
        guard !transactions.isEmpty else { throw BulkTransactionError.emptySelection }
        let recoveryIDs = Set(
            try context.fetch(FetchDescriptor<AASettlement>()).map(\.recoveryTransactionID)
        )
        guard transactions.allSatisfy({ !recoveryIDs.contains($0.id) }) else {
            throw LedgerError.aaRecoveryManaged
        }
        if changesCategory, let category {
            let valid = transactions.allSatisfy { transaction in
                (transaction.type == .expense && category.type == .expense)
                    || (transaction.type == .income && category.type == .income)
            }
            guard valid else { throw BulkTransactionError.mixedCategoryTypes }
        }
        do {
            for transaction in transactions {
                if changesCategory { transaction.category = category }
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
