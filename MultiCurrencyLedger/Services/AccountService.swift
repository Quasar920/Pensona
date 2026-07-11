import Foundation
import SwiftData

@MainActor
final class AccountService {
    private let context: ModelContext
    private let ledger: LedgerService

    init(context: ModelContext) {
        self.context = context
        ledger = LedgerService(context: context)
    }

    func createAccount(
        name: String,
        type: AccountType,
        note: String?,
        book: LedgerBook? = nil
    ) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError("请输入账户名称") }
        let account = Account(name: trimmed, type: type, note: note, book: book)
        context.insert(account)
        try context.save()
        return account
    }

    func addWallet(
        currency: SupportedCurrency,
        initialBalance: Decimal,
        to account: Account
    ) throws -> CurrencyWallet {
        guard !account.wallets.contains(where: { $0.currencyCode == currency.rawValue }) else {
            throw LedgerError.duplicateCurrency
        }
        guard initialBalance >= 0 else { throw LedgerError.invalidAmount }

        let wallet = CurrencyWallet(currency: currency, account: account)
        context.insert(wallet)
        if initialBalance > 0 {
            let isLiability = account.type.isLiability
            _ = try ledger.createAdjustment(
                amount: initialBalance,
                wallet: wallet,
                direction: isLiability ? .decrease : .increase,
                reason: isLiability ? "初始欠款" : "初始余额",
                date: .now,
                note: nil
            )
        } else {
            try context.save()
        }
        return wallet
    }

    func deleteAccount(_ account: Account, transactions: [LedgerTransaction]) throws {
        let isReferenced = transactions.contains {
            $0.sourceAccount === account || $0.destinationAccount === account
        }
        guard !isReferenced else { throw LedgerError.accountInUse }
        context.delete(account)
        try context.save()
    }
}

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
