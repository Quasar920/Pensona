import Foundation
import SwiftData

@MainActor
final class AccountService {
    private let context: ModelContext
    private let ledger: LedgerService
    private let cardIdentityStore: AccountCardIdentityStore

    init(
        context: ModelContext,
        cardIdentityStore: AccountCardIdentityStore = AccountCardIdentityStore()
    ) {
        self.context = context
        self.cardIdentityStore = cardIdentityStore
        ledger = LedgerService(context: context)
    }

    func createAccount(
        name: String,
        type: AccountType,
        note: String?,
        cardLastFour: String? = nil,
        book: LedgerBook? = nil
    ) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError("请输入账户名称") }
        let cleanLastFour = try AccountCardIdentityStore.validated(cardLastFour)
        let account = Account(name: trimmed, type: type, note: note, book: book)
        context.insert(account)
        try context.save()
        try cardIdentityStore.setLastFour(cleanLastFour, for: account.id)
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
        let walletIDs = Set(account.wallets.map(\.id))
        let isReferenced = transactions.contains {
            $0.sourceAccount === account
                || $0.destinationAccount === account
                || $0.sourceWallet.map { walletIDs.contains($0.id) } == true
                || $0.destinationWallet.map { walletIDs.contains($0.id) } == true
                || $0.feeWallet.map { walletIDs.contains($0.id) } == true
                || $0.paymentParts.contains(where: { part in
                    part.wallet.map { walletIDs.contains($0.id) } == true
                })
        }
        guard !isReferenced else { throw LedgerError.accountInUse }
        let accountID = account.id
        context.delete(account)
        try context.save()
        cardIdentityStore.removeLastFour(for: accountID)
    }

    func update(
        _ account: Account,
        name: String,
        type: AccountType,
        note: String?,
        sortOrder: Int,
        isHidden: Bool,
        cardLastFour: String?
    ) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("请输入账户名称") }
        let cleanLastFour = try AccountCardIdentityStore.validated(cardLastFour)
        account.name = cleanName
        account.typeRawValue = type.rawValue
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        account.note = cleanNote?.isEmpty == true ? nil : cleanNote
        account.sortOrder = sortOrder
        account.isHidden = isHidden
        account.updatedAt = .now
        try context.save()
        try cardIdentityStore.setLastFour(cleanLastFour, for: account.id)
    }

    func setArchived(_ archived: Bool, account: Account) throws {
        account.isArchived = archived
        account.isHidden = archived
        account.updatedAt = .now
        try context.save()
    }

    func setWalletEnabled(_ enabled: Bool, wallet: CurrencyWallet) throws {
        wallet.isEnabled = enabled
        wallet.updatedAt = .now
        try context.save()
    }

    func deleteWallet(_ wallet: CurrencyWallet, transactions: [LedgerTransaction]) throws {
        let isReferenced = transactions.contains {
            $0.sourceWallet?.id == wallet.id
                || $0.destinationWallet?.id == wallet.id
                || $0.feeWallet?.id == wallet.id
                || $0.paymentParts.contains(where: { $0.wallet?.id == wallet.id })
        }
        guard wallet.balance == 0, !isReferenced else { throw LedgerError.walletInUse }
        context.delete(wallet)
        try context.save()
    }
}

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
