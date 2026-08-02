import Foundation
import SwiftData

enum LedgerBookAccess {
    @MainActor
    static func requireActiveBook(in context: ModelContext, id: UUID) throws -> LedgerBook {
        let descriptor = FetchDescriptor<LedgerBook>(
            predicate: #Predicate { $0.id == id }
        )
        guard let book = try context.fetch(descriptor).first else {
            throw LedgerError.missingBook
        }
        guard !book.isArchived else { throw LedgerError.bookArchived }
        return book
    }

    @MainActor
    static func requireActiveBook(in context: ModelContext, for account: Account) throws {
        guard let bookID = account.book?.id else { return }
        _ = try requireActiveBook(in: context, id: bookID)
    }

    @MainActor
    static func requireActiveBook(in context: ModelContext, for wallet: CurrencyWallet) throws {
        guard let account = wallet.account else { throw LedgerError.missingWallet }
        try requireActiveBook(in: context, for: account)
    }

    @MainActor
    static func requireActiveBook(in context: ModelContext, for transaction: LedgerTransaction) throws {
        guard let bookID = transaction.bookID else { throw LedgerError.missingBook }
        _ = try requireActiveBook(in: context, id: bookID)
    }
}
