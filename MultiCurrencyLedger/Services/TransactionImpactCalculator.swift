import Foundation

struct WalletDelta: Equatable {
    let wallet: CurrencyWallet
    let amount: Decimal

    static func == (lhs: WalletDelta, rhs: WalletDelta) -> Bool {
        lhs.wallet.id == rhs.wallet.id && lhs.amount == rhs.amount
    }
}

/// Validates a draft and turns it into deterministic wallet balance changes.
/// The calculator is pure: it never applies the returned deltas.
struct TransactionImpactCalculator {
    func deltas(for draft: TransactionDraft) throws -> [WalletDelta] {
        guard draft.amount > 0 else { throw LedgerError.invalidAmount }
        guard let sourceWallet = draft.sourceWallet else { throw LedgerError.missingWallet }

        var changes: [WalletDelta] = []

        switch draft.type {
        case .expense:
            try validateCategory(draft.category, expected: .expense)
            try appendPayments(from: draft, sign: -1, fallback: sourceWallet, to: &changes)
        case .income:
            try validateCategory(draft.category, expected: .income)
            try appendPayments(from: draft, sign: 1, fallback: sourceWallet, to: &changes)
        case .transfer:
            let destinationWallet = try validateDestination(draft, sourceWallet: sourceWallet)
            guard sourceWallet.currencyCode == destinationWallet.currencyCode else {
                throw LedgerError.currencyMismatch
            }
            changes.append(WalletDelta(wallet: sourceWallet, amount: -draft.amount))
            changes.append(WalletDelta(wallet: destinationWallet, amount: draft.amount))
            try appendFee(from: draft, to: &changes)
        case .exchange:
            let destinationWallet = try validateDestination(draft, sourceWallet: sourceWallet)
            guard sourceWallet.currencyCode != destinationWallet.currencyCode else {
                throw LedgerError.sameCurrencyExchange
            }
            guard let destinationAmount = draft.destinationAmount, destinationAmount > 0 else {
                throw LedgerError.destinationAmountRequired
            }
            changes.append(WalletDelta(wallet: sourceWallet, amount: -draft.amount))
            changes.append(WalletDelta(wallet: destinationWallet, amount: destinationAmount))
            try appendFee(from: draft, to: &changes)
        case .adjustment:
            guard let direction = draft.adjustmentDirection,
                  let reason = draft.adjustmentReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reason.isEmpty else {
                throw LedgerError.missingAdjustment
            }
            let sign: Decimal = direction == .decrease ? -1 : 1
            changes.append(WalletDelta(wallet: sourceWallet, amount: sign * draft.amount))
        }

        return aggregate(changes)
    }

    private func validateCategory(
        _ category: LedgerCategory?,
        expected: CategoryKind
    ) throws {
        guard category == nil || category?.type == expected else {
            throw LedgerError.categoryMismatch
        }
    }

    private func validateDestination(
        _ draft: TransactionDraft,
        sourceWallet: CurrencyWallet
    ) throws -> CurrencyWallet {
        guard let destinationWallet = draft.destinationWallet else {
            throw LedgerError.missingWallet
        }
        guard destinationWallet.id != sourceWallet.id else { throw LedgerError.sameWallet }
        return destinationWallet
    }

    private func appendFee(
        from draft: TransactionDraft,
        to changes: inout [WalletDelta]
    ) throws {
        guard let feeAmount = draft.feeAmount else { return }
        guard feeAmount > 0 else { throw LedgerError.invalidAmount }
        guard let feeWallet = draft.feeWallet else { throw LedgerError.missingWallet }
        changes.append(WalletDelta(wallet: feeWallet, amount: -feeAmount))
    }

    private func appendPayments(
        from draft: TransactionDraft,
        sign: Decimal,
        fallback sourceWallet: CurrencyWallet,
        to changes: inout [WalletDelta]
    ) throws {
        guard !draft.paymentParts.isEmpty else {
            changes.append(WalletDelta(wallet: sourceWallet, amount: sign * draft.amount))
            return
        }
        guard draft.paymentParts.count >= 2,
              draft.paymentParts.allSatisfy({ $0.amount > 0 }),
              draft.paymentParts.reduce(Decimal.zero, { $0 + $1.amount }) == draft.amount else {
            throw LedgerError.paymentPartsMismatch
        }
        guard draft.paymentParts.allSatisfy({ $0.wallet.currencyCode == sourceWallet.currencyCode }) else {
            throw LedgerError.paymentCurrencyMismatch
        }
        let walletIDs = draft.paymentParts.map { $0.wallet.id }
        guard Set(walletIDs).count == walletIDs.count else {
            throw LedgerError.duplicatePaymentWallet
        }
        changes.append(contentsOf: draft.paymentParts.map {
            WalletDelta(wallet: $0.wallet, amount: sign * $0.amount)
        })
    }

    private func aggregate(_ changes: [WalletDelta]) -> [WalletDelta] {
        var result: [WalletDelta] = []
        var indexes: [UUID: Int] = [:]
        for change in changes {
            if let index = indexes[change.wallet.id] {
                let existing = result[index]
                result[index] = WalletDelta(
                    wallet: existing.wallet,
                    amount: existing.amount + change.amount
                )
            } else {
                indexes[change.wallet.id] = result.count
                result.append(change)
            }
        }
        return result
    }
}
