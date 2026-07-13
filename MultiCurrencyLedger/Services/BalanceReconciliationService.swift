import Foundation
import SwiftData

struct WalletReconciliationResult: Identifiable {
    let wallet: CurrencyWallet
    let expectedBalance: Decimal

    var id: UUID { wallet.id }
    var currentBalance: Decimal { wallet.balance }
    var difference: Decimal { expectedBalance - currentBalance }
    var isBalanced: Bool { difference == 0 }
}

@MainActor
final class BalanceReconciliationService {
    private let context: ModelContext
    private let calculator = TransactionImpactCalculator()

    init(context: ModelContext) {
        self.context = context
    }

    func result(
        for wallet: CurrencyWallet,
        transactions: [LedgerTransaction]
    ) throws -> WalletReconciliationResult {
        var expected = Decimal.zero
        for transaction in transactions {
            for delta in try calculator.deltas(for: TransactionDraft(transaction: transaction))
            where delta.wallet.id == wallet.id {
                expected += delta.amount
            }
        }
        return WalletReconciliationResult(wallet: wallet, expectedBalance: expected)
    }

    func results(
        for wallets: [CurrencyWallet],
        transactions: [LedgerTransaction]
    ) throws -> [WalletReconciliationResult] {
        try wallets.map { try result(for: $0, transactions: transactions) }
    }

    /// Rebuilds a derived wallet balance from its complete transaction history.
    func rebuild(
        _ wallet: CurrencyWallet,
        transactions: [LedgerTransaction]
    ) throws {
        wallet.balance = try result(for: wallet, transactions: transactions).expectedBalance
        wallet.updatedAt = .now
        try context.save()
    }
}
