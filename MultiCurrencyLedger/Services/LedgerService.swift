import Foundation
import SwiftData

enum LedgerError: LocalizedError, Equatable {
    case invalidAmount
    case currencyMismatch
    case sameWallet
    case missingWallet
    case duplicateCurrency
    case accountInUse
    case categoryMismatch
    case destinationAmountRequired
    case sameCurrencyExchange
    case missingAdjustment
    case paymentPartsMismatch
    case paymentCurrencyMismatch
    case duplicatePaymentWallet
    case relatedTransactionExists

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "金额必须大于 0"
        case .currencyMismatch: "转账仅支持相同币种"
        case .sameWallet: "来源和目标钱包不能相同"
        case .missingWallet: "交易关联的钱包不存在"
        case .duplicateCurrency: "该账户已添加这个币种"
        case .accountInUse: "该账户仍被交易引用，不能删除"
        case .categoryMismatch: "分类与交易类型不匹配"
        case .destinationAmountRequired: "请输入大于 0 的换入金额"
        case .sameCurrencyExchange: "换汇必须选择两个不同币种的钱包"
        case .missingAdjustment: "请选择调整方向并填写调整原因"
        case .paymentPartsMismatch: "组合付款分项之和必须等于交易总额"
        case .paymentCurrencyMismatch: "组合付款只能使用相同币种的钱包"
        case .duplicatePaymentWallet: "组合付款不能重复选择同一个钱包"
        case .relatedTransactionExists: "请先删除这笔支出关联的退款或报销交易"
        }
    }
}

@MainActor
final class LedgerService {
    private let context: ModelContext
    private let impactCalculator = TransactionImpactCalculator()

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create(_ draft: TransactionDraft) throws -> LedgerTransaction {
        try create(draft) { _ in }
    }

    /// Allows automation services to insert their unique occurrence marker in
    /// the same save as the generated transaction and wallet balance changes.
    @discardableResult
    func create(
        _ draft: TransactionDraft,
        configureBeforeSave: (LedgerTransaction) throws -> Void
    ) throws -> LedgerTransaction {
        _ = try impactCalculator.deltas(for: draft)
        return try persistNew(draft.makeTransaction(), configureBeforeSave: configureBeforeSave)
    }

    @discardableResult
    func createExpense(
        amount: Decimal,
        wallet: CurrencyWallet,
        category: LedgerCategory?,
        date: Date,
        note: String?,
        merchantOrCounterparty: String? = nil
    ) throws -> LedgerTransaction {
        try create(TransactionDraft(
            type: .expense,
            amount: amount,
            sourceWallet: wallet,
            date: date,
            note: note,
            merchantOrCounterparty: merchantOrCounterparty,
            category: category
        ))
    }

    @discardableResult
    func createIncome(
        amount: Decimal,
        wallet: CurrencyWallet,
        category: LedgerCategory?,
        date: Date,
        note: String?,
        merchantOrCounterparty: String? = nil
    ) throws -> LedgerTransaction {
        try create(TransactionDraft(
            type: .income,
            amount: amount,
            sourceWallet: wallet,
            date: date,
            note: note,
            merchantOrCounterparty: merchantOrCounterparty,
            category: category
        ))
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
        try create(TransactionDraft(
            type: .transfer,
            amount: amount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            feeAmount: feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: note
        ))
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
        try create(TransactionDraft(
            type: .exchange,
            amount: sourceAmount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            destinationAmount: destinationAmount,
            feeAmount: feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: note
        ))
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
        try create(TransactionDraft(
            type: .adjustment,
            amount: amount,
            sourceWallet: wallet,
            date: date,
            note: note,
            adjustmentDirection: direction,
            adjustmentReason: reason
        ))
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
        try deleteTransactions([transaction])
    }

    func deleteTransactions(_ transactions: [LedgerTransaction]) throws {
        guard !transactions.isEmpty else { return }
        let snapshots = snapshots(for: transactions)
        var attachmentPaths: [String] = []
        do {
            let allRelations = try context.fetch(FetchDescriptor<TransactionRelation>())
            let transactionIDs = Set(transactions.map(\.id))
            if allRelations.contains(where: {
                transactionIDs.contains($0.originalTransactionID)
                    && !transactionIDs.contains($0.relatedTransactionID)
            }) {
                throw LedgerError.relatedTransactionExists
            }
            for relation in allRelations where
                transactionIDs.contains(relation.originalTransactionID)
                    || transactionIDs.contains(relation.relatedTransactionID) {
                context.delete(relation)
            }
            let allAttachments = try context.fetch(FetchDescriptor<TransactionAttachment>())
            for attachment in allAttachments where transactionIDs.contains(attachment.transactionID) {
                attachmentPaths.append(attachment.relativePath)
                context.delete(attachment)
            }
            for transaction in transactions {
                try reverseTransaction(transaction)
                context.delete(transaction)
            }
            try context.save()
            let store = AttachmentStore()
            for path in attachmentPaths { try? store.remove(relativePath: path) }
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
        try replaceTransaction(existing, with: TransactionDraft(transaction: replacement))
    }

    func replaceTransaction(
        _ existing: LedgerTransaction,
        with draft: TransactionDraft
    ) throws {
        _ = try impactCalculator.deltas(for: draft)
        let replacement = draft.makeTransaction()
        let snapshots = snapshots(for: [existing, replacement])
        do {
            try reverseTransaction(existing)
            let oldPaymentParts = existing.paymentParts
            draft.apply(to: existing)
            for part in oldPaymentParts { context.delete(part) }
            try applyTransaction(existing)
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

    private func persistNew(
        _ transaction: LedgerTransaction,
        configureBeforeSave: (LedgerTransaction) throws -> Void = { _ in }
    ) throws -> LedgerTransaction {
        let snapshots = snapshots(for: [transaction])
        do {
            try applyTransaction(transaction)
            context.insert(transaction)
            try configureBeforeSave(transaction)
            try context.save()
            return transaction
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    private func changeBalances(for transaction: LedgerTransaction, multiplier: Decimal) throws {
        for delta in try impactCalculator.deltas(for: TransactionDraft(transaction: transaction)) {
            try adjust(delta.wallet, by: delta.amount * multiplier)
        }
    }

    private func adjust(_ wallet: CurrencyWallet?, by amount: Decimal) throws {
        guard let wallet else { throw LedgerError.missingWallet }
        wallet.balance += amount
        wallet.updatedAt = .now
    }

    private func snapshots(for transactions: [LedgerTransaction]) -> [WalletSnapshot] {
        var seen = Set<ObjectIdentifier>()
        return transactions
            .flatMap { transaction in
                [transaction.sourceWallet, transaction.destinationWallet, transaction.feeWallet]
                    + transaction.paymentParts.map(\.wallet)
            }
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
