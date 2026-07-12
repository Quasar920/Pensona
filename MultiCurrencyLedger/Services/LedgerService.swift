import Foundation
import SwiftData

enum LedgerError: LocalizedError, Equatable {
    case invalidAmount
    case currencyMismatch
    case sameWallet
    case missingWallet
    case duplicateCurrency
    case accountInUse

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "金额必须大于 0"
        case .currencyMismatch: "转账仅支持相同币种"
        case .sameWallet: "来源和目标钱包不能相同"
        case .missingWallet: "交易关联的钱包不存在"
        case .duplicateCurrency: "该账户已添加这个币种"
        case .accountInUse: "该账户仍被交易引用，不能删除"
        }
    }
}

@MainActor
final class LedgerService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func createExpense(
        amount: Decimal,
        wallet: CurrencyWallet,
        category: LedgerCategory?,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try validate(amount)
        let transaction = LedgerTransaction(
            type: .expense,
            amount: amount,
            currencyCode: wallet.currencyCode,
            date: date,
            note: note,
            sourceAccount: wallet.account,
            sourceWallet: wallet,
            sourceAmount: amount,
            sourceCurrencyCode: wallet.currencyCode,
            category: category
        )
        return try persistNew(transaction)
    }

    @discardableResult
    func createIncome(
        amount: Decimal,
        wallet: CurrencyWallet,
        category: LedgerCategory?,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try validate(amount)
        let transaction = LedgerTransaction(
            type: .income,
            amount: amount,
            currencyCode: wallet.currencyCode,
            date: date,
            note: note,
            sourceAccount: wallet.account,
            sourceWallet: wallet,
            sourceAmount: amount,
            sourceCurrencyCode: wallet.currencyCode,
            category: category
        )
        return try persistNew(transaction)
    }

    @discardableResult
    func createTransfer(
        amount: Decimal,
        from sourceWallet: CurrencyWallet,
        to destinationWallet: CurrencyWallet,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try validate(amount)
        guard sourceWallet !== destinationWallet else { throw LedgerError.sameWallet }
        guard sourceWallet.currencyCode == destinationWallet.currencyCode else {
            throw LedgerError.currencyMismatch
        }
        if let feeAmount { try validate(feeAmount) }
        if feeAmount != nil, feeWallet == nil { throw LedgerError.missingWallet }

        let transaction = LedgerTransaction(
            type: .transfer,
            date: date,
            note: note,
            sourceAccount: sourceWallet.account,
            sourceWallet: sourceWallet,
            destinationAccount: destinationWallet.account,
            destinationWallet: destinationWallet,
            sourceAmount: amount,
            sourceCurrencyCode: sourceWallet.currencyCode,
            destinationAmount: amount,
            destinationCurrencyCode: destinationWallet.currencyCode,
            feeAmount: feeAmount,
            feeCurrencyCode: feeWallet?.currencyCode,
            feeWallet: feeWallet
        )
        return try persistNew(transaction)
    }

    @discardableResult
    func createExchange(
        sourceAmount: Decimal,
        from sourceWallet: CurrencyWallet,
        destinationAmount: Decimal,
        to destinationWallet: CurrencyWallet,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try validate(sourceAmount)
        try validate(destinationAmount)
        guard sourceWallet !== destinationWallet else { throw LedgerError.sameWallet }
        if let feeAmount { try validate(feeAmount) }
        if feeAmount != nil, feeWallet == nil { throw LedgerError.missingWallet }

        let transaction = LedgerTransaction(
            type: .exchange,
            date: date,
            note: note,
            sourceAccount: sourceWallet.account,
            sourceWallet: sourceWallet,
            destinationAccount: destinationWallet.account,
            destinationWallet: destinationWallet,
            sourceAmount: sourceAmount,
            sourceCurrencyCode: sourceWallet.currencyCode,
            destinationAmount: destinationAmount,
            destinationCurrencyCode: destinationWallet.currencyCode,
            feeAmount: feeAmount,
            feeCurrencyCode: feeWallet?.currencyCode,
            feeWallet: feeWallet,
            exchangeRate: destinationAmount / sourceAmount
        )
        return try persistNew(transaction)
    }

    @discardableResult
    func createAdjustment(
        amount: Decimal,
        wallet: CurrencyWallet,
        direction: AdjustmentDirection,
        reason: String,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try validate(amount)
        let transaction = LedgerTransaction(
            type: .adjustment,
            amount: amount,
            currencyCode: wallet.currencyCode,
            date: date,
            note: note,
            sourceAccount: wallet.account,
            sourceWallet: wallet,
            sourceAmount: amount,
            sourceCurrencyCode: wallet.currencyCode,
            adjustmentDirection: direction,
            adjustmentReason: reason
        )
        return try persistNew(transaction)
    }

    /// Persists a recognition-confirmed transaction and its non-sensitive audit
    /// record in the same save operation. Neither OCR text nor screenshot data is
    /// accepted here, so this boundary cannot accidentally retain either.
    @discardableResult
    func persistRecognized(
        _ transaction: LedgerTransaction,
        importRecord: RecognitionImportRecord
    ) throws -> LedgerTransaction {
        let snapshots = snapshots(for: [transaction])
        do {
            try applyTransaction(transaction)
            importRecord.transactionID = transaction.id
            transaction.recognitionImportID = importRecord.id
            context.insert(transaction)
            context.insert(importRecord)
            try context.save()
            return transaction
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    func deleteTransaction(_ transaction: LedgerTransaction) throws {
        let snapshots = snapshots(for: [transaction])
        do {
            try reverseTransaction(transaction)
            context.delete(transaction)
            try context.save()
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    func replaceTransaction(
        _ existing: LedgerTransaction,
        with replacement: LedgerTransaction
    ) throws {
        let snapshots = snapshots(for: [existing, replacement])
        do {
            try reverseTransaction(existing)
            try applyTransaction(replacement)
            context.insert(replacement)
            context.delete(existing)
            try context.save()
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    func applyTransaction(_ transaction: LedgerTransaction) throws {
        try changeBalances(for: transaction, multiplier: 1)
    }

    func reverseTransaction(_ transaction: LedgerTransaction) throws {
        try changeBalances(for: transaction, multiplier: -1)
    }

    private func persistNew(_ transaction: LedgerTransaction) throws -> LedgerTransaction {
        let snapshots = snapshots(for: [transaction])
        do {
            try applyTransaction(transaction)
            context.insert(transaction)
            try context.save()
            return transaction
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    private func changeBalances(for transaction: LedgerTransaction, multiplier: Decimal) throws {
        switch transaction.type {
        case .expense:
            try adjust(transaction.sourceWallet, by: -(transaction.sourceAmount ?? transaction.amount ?? 0) * multiplier)
        case .income:
            try adjust(transaction.sourceWallet, by: (transaction.sourceAmount ?? transaction.amount ?? 0) * multiplier)
        case .transfer, .exchange:
            try adjust(transaction.sourceWallet, by: -(transaction.sourceAmount ?? 0) * multiplier)
            try adjust(transaction.destinationWallet, by: (transaction.destinationAmount ?? 0) * multiplier)
            if let feeAmount = transaction.feeAmount, feeAmount > 0 {
                try adjust(transaction.feeWallet, by: -feeAmount * multiplier)
            }
        case .adjustment:
            let sign: Decimal = transaction.adjustmentDirection == .decrease ? -1 : 1
            try adjust(transaction.sourceWallet, by: sign * (transaction.sourceAmount ?? transaction.amount ?? 0) * multiplier)
        }
    }

    private func adjust(_ wallet: CurrencyWallet?, by amount: Decimal) throws {
        guard let wallet else { throw LedgerError.missingWallet }
        wallet.balance += amount
        wallet.updatedAt = .now
    }

    private func validate(_ amount: Decimal) throws {
        guard amount > 0 else { throw LedgerError.invalidAmount }
    }

    private func snapshots(for transactions: [LedgerTransaction]) -> [WalletSnapshot] {
        var seen = Set<ObjectIdentifier>()
        return transactions
            .flatMap { [$0.sourceWallet, $0.destinationWallet, $0.feeWallet] }
            .compactMap { $0 }
            .compactMap { wallet in
                guard seen.insert(ObjectIdentifier(wallet)).inserted else { return nil }
                return WalletSnapshot(wallet: wallet, balance: wallet.balance, updatedAt: wallet.updatedAt)
            }
    }

    private func restore(_ snapshots: [WalletSnapshot]) {
        for snapshot in snapshots {
            snapshot.wallet.balance = snapshot.balance
            snapshot.wallet.updatedAt = snapshot.updatedAt
        }
    }
}

private struct WalletSnapshot {
    let wallet: CurrencyWallet
    let balance: Decimal
    let updatedAt: Date
}
