import Foundation
import SwiftData

enum LedgerError: LocalizedError, Equatable {
    case invalidAmount
    case currencyMismatch
    case sameWallet
    case missingWallet
    case duplicateCurrency
    case accountInUse
    case walletInUse
    case bookInUse
    case categoryMismatch
    case destinationAmountRequired
    case sameCurrencyExchange
    case missingAdjustment
    case paymentPartsMismatch
    case paymentCurrencyMismatch
    case duplicatePaymentWallet
    case relatedTransactionExists
    case aaSettlementExists
    case aaRecoveryManaged
    case missingBook

    var errorDescription: String? {
        switch self {
        case .invalidAmount: AppLocalization.string( "金额必须大于 0")
        case .currencyMismatch: AppLocalization.string( "转账仅支持相同币种")
        case .sameWallet: AppLocalization.string( "来源和目标钱包不能相同")
        case .missingWallet: AppLocalization.string( "交易关联的钱包不存在")
        case .duplicateCurrency: AppLocalization.string( "该账户已添加这个币种")
        case .accountInUse: AppLocalization.string( "该账户仍被交易引用，不能删除")
        case .walletInUse: AppLocalization.string( "该钱包仍有余额或历史交易，只能停用")
        case .bookInUse: AppLocalization.string( "账本仍有数据或是唯一账本，不能删除")
        case .categoryMismatch: AppLocalization.string( "分类与交易类型不匹配")
        case .destinationAmountRequired: AppLocalization.string( "请输入大于 0 的换入金额")
        case .sameCurrencyExchange: AppLocalization.string( "换汇必须选择两个不同币种的钱包")
        case .missingAdjustment: AppLocalization.string( "请选择调整方向并填写调整原因")
        case .paymentPartsMismatch: AppLocalization.string( "组合付款分项之和必须等于交易总额")
        case .paymentCurrencyMismatch: AppLocalization.string( "组合付款只能使用相同币种的钱包")
        case .duplicatePaymentWallet: AppLocalization.string( "组合付款不能重复选择同一个钱包")
        case .relatedTransactionExists: AppLocalization.string( "请先删除这笔支出关联的退款或报销交易")
        case .aaSettlementExists: AppLocalization.string( "请先删除这笔支出关联的 AA 收款记录")
        case .aaRecoveryManaged: AppLocalization.string( "AA 收款只能从原支出的 AA 收款历史中处理")
        case .missingBook: AppLocalization.string( "交易必须归属一个存在的账本")
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
    func create(_ draft: TransactionDraft, bookID: UUID) throws -> LedgerTransaction {
        try create(draft, bookID: bookID) { _ in }
    }

    /// Allows automation services to insert their unique occurrence marker in
    /// the same save as the generated transaction and wallet balance changes.
    @discardableResult
    func create(
        _ draft: TransactionDraft,
        bookID: UUID,
        configureBeforeSave: (LedgerTransaction) throws -> Void
    ) throws -> LedgerTransaction {
        try requireBook(bookID)
        _ = try impactCalculator.deltas(for: draft)
        return try persistNew(draft.makeTransaction(bookID: bookID), configureBeforeSave: configureBeforeSave)
    }

    /// Validates and writes a whole import batch in one transaction. No wallet
    /// balance or row is retained if any row fails.
    func createBatch(
        _ drafts: [TransactionDraft],
        bookID: UUID,
        configureBeforeSave: ([LedgerTransaction]) throws -> Void
    ) throws -> [LedgerTransaction] {
        guard !drafts.isEmpty else { return [] }
        try requireBook(bookID)
        for draft in drafts { _ = try impactCalculator.deltas(for: draft) }
        let transactions = drafts.map { $0.makeTransaction(bookID: bookID) }
        let snapshots = snapshots(for: transactions)
        do {
            for transaction in transactions {
                try applyTransaction(transaction)
                context.insert(transaction)
            }
            try configureBeforeSave(transactions)
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
            return transactions
        } catch {
            context.rollback()
            restore(snapshots)
            throw error
        }
    }

    @discardableResult
    func createExpense(
        bookID: UUID,
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
        ), bookID: bookID)
    }

    @discardableResult
    func createIncome(
        bookID: UUID,
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
        ), bookID: bookID)
    }

    @discardableResult
    func createTransfer(
        bookID: UUID,
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
        ), bookID: bookID)
    }

    @discardableResult
    func createExchange(
        bookID: UUID,
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
        ), bookID: bookID)
    }

    @discardableResult
    func createAdjustment(
        bookID: UUID,
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
        ), bookID: bookID)
    }

    /// Persists a recognition-confirmed transaction and its non-sensitive audit
    /// record in the same save operation. Neither OCR text nor screenshot data is
    /// accepted here, so this boundary cannot accidentally retain either.
    @discardableResult
    func persistRecognized(
        _ transaction: LedgerTransaction,
        importRecord: RecognitionImportRecord,
        bookID: UUID
    ) throws -> LedgerTransaction {
        try requireBook(bookID)
        transaction.bookID = bookID
        let snapshots = snapshots(for: [transaction])
        do {
            try applyTransaction(transaction)
            importRecord.transactionID = transaction.id
            transaction.recognitionImportID = importRecord.id
            context.insert(transaction)
            context.insert(importRecord)
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
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

    func deleteTransactions(
        _ transactions: [LedgerTransaction],
        configureBeforeSave: () throws -> Void = {}
    ) throws {
        try deleteTransactions(
            transactions,
            allowedAASettlementIDs: [],
            configureBeforeSave: configureBeforeSave
        )
    }

    func deleteAASettlementTransaction(
        _ transaction: LedgerTransaction,
        settlement: AASettlement
    ) throws {
        guard settlement.recoveryTransactionID == transaction.id else {
            throw LedgerError.aaRecoveryManaged
        }
        try deleteTransactions(
            [transaction],
            allowedAASettlementIDs: [settlement.id]
        )
    }

    private func deleteTransactions(
        _ transactions: [LedgerTransaction],
        allowedAASettlementIDs: Set<UUID>,
        configureBeforeSave: () throws -> Void = {}
    ) throws {
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

            let allSplits = try context.fetch(FetchDescriptor<AASplit>())
            let allAASettlements = try context.fetch(FetchDescriptor<AASettlement>())
            let splitByID = Dictionary(uniqueKeysWithValues: allSplits.map { ($0.id, $0) })
            for settlement in allAASettlements where transactionIDs.contains(settlement.recoveryTransactionID) {
                let originalIsAlsoDeleted = splitByID[settlement.splitID]
                    .map { transactionIDs.contains($0.originalTransactionID) } ?? false
                guard allowedAASettlementIDs.contains(settlement.id) || originalIsAlsoDeleted else {
                    throw LedgerError.aaRecoveryManaged
                }
            }
            for split in allSplits where transactionIDs.contains(split.originalTransactionID) {
                let pendingRecoveries = allAASettlements.filter {
                    $0.splitID == split.id && !transactionIDs.contains($0.recoveryTransactionID)
                }
                guard pendingRecoveries.isEmpty else { throw LedgerError.aaSettlementExists }
            }

            for relation in allRelations where
                transactionIDs.contains(relation.originalTransactionID)
                    || transactionIDs.contains(relation.relatedTransactionID) {
                context.delete(relation)
            }
            let deletedSplitIDs = Set(allSplits.filter {
                transactionIDs.contains($0.originalTransactionID)
            }.map(\.id))
            for settlement in allAASettlements where
                transactionIDs.contains(settlement.recoveryTransactionID)
                    || deletedSplitIDs.contains(settlement.splitID) {
                context.delete(settlement)
            }
            for split in allSplits where deletedSplitIDs.contains(split.id) {
                context.delete(split)
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
            try configureBeforeSave()
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
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
        with draft: TransactionDraft,
        configureBeforeSave: (LedgerTransaction) throws -> Void = { _ in }
    ) throws {
        _ = try impactCalculator.deltas(for: draft)
        let aaSettlements = try context.fetch(FetchDescriptor<AASettlement>())
        guard !aaSettlements.contains(where: { $0.recoveryTransactionID == existing.id }) else {
            throw LedgerError.aaRecoveryManaged
        }
        guard let bookID = existing.bookID else { throw LedgerError.missingBook }
        let replacement = draft.makeTransaction(bookID: bookID)
        let snapshots = snapshots(for: [existing, replacement])
        let transactionSnapshot = LedgerTransactionSnapshot(transaction: existing)
        do {
            try reverseTransaction(existing)
            let oldPaymentParts = existing.paymentParts
            draft.apply(to: existing)
            for part in oldPaymentParts { context.delete(part) }
            try applyTransaction(existing)
            try configureBeforeSave(existing)
            let hasAASplit = try context.fetch(FetchDescriptor<AASplit>())
                .contains(where: { $0.originalTransactionID == existing.id })
            if hasAASplit, existing.type != .expense {
                throw AASplitError.expenseRequired
            }
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
        } catch {
            context.rollback()
            transactionSnapshot.restore()
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

    func moveTransaction(_ transaction: LedgerTransaction, toBookID bookID: UUID) throws {
        try requireBook(bookID)
        transaction.bookID = bookID
        transaction.updatedAt = .now
        try context.save()
        NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
    }

    private func persistNew(
        _ transaction: LedgerTransaction,
        configureBeforeSave: (LedgerTransaction) throws -> Void = { _ in }
    ) throws -> LedgerTransaction {
        guard transaction.bookID != nil else { throw LedgerError.missingBook }
        let snapshots = snapshots(for: [transaction])
        do {
            try applyTransaction(transaction)
            context.insert(transaction)
            try configureBeforeSave(transaction)
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
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

    private func requireBook(_ bookID: UUID) throws {
        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard books.contains(where: { $0.id == bookID }) else { throw LedgerError.missingBook }
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

extension Notification.Name {
    static let ledgerTransactionsDidChange = Notification.Name("ledgerTransactionsDidChange")
}

private struct WalletSnapshot {
    let wallet: CurrencyWallet
    let balance: Decimal
    let updatedAt: Date
}

private struct LedgerTransactionSnapshot {
    let transaction: LedgerTransaction
    let typeRawValue: String
    let amount: Decimal?
    let currencyCode: String?
    let date: Date
    let note: String?
    let updatedAt: Date
    let sourceAmount: Decimal?
    let sourceCurrencyCode: String?
    let destinationAmount: Decimal?
    let destinationCurrencyCode: String?
    let feeAmount: Decimal?
    let feeCurrencyCode: String?
    let exchangeRate: Decimal?
    let adjustmentDirectionRawValue: String?
    let adjustmentReason: String?
    let merchantOrCounterparty: String?
    let originalAmount: Decimal?
    let discountAmount: Decimal?
    let recognitionImportID: UUID?
    let bookID: UUID?
    let reimbursementStatusRawValue: String
    let sourceAccount: Account?
    let sourceWallet: CurrencyWallet?
    let destinationAccount: Account?
    let destinationWallet: CurrencyWallet?
    let feeWallet: CurrencyWallet?
    let category: LedgerCategory?
    let tags: [TransactionTag]
    let paymentParts: [TransactionPaymentPart]

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        typeRawValue = transaction.typeRawValue
        amount = transaction.amount
        currencyCode = transaction.currencyCode
        date = transaction.date
        note = transaction.note
        updatedAt = transaction.updatedAt
        sourceAmount = transaction.sourceAmount
        sourceCurrencyCode = transaction.sourceCurrencyCode
        destinationAmount = transaction.destinationAmount
        destinationCurrencyCode = transaction.destinationCurrencyCode
        feeAmount = transaction.feeAmount
        feeCurrencyCode = transaction.feeCurrencyCode
        exchangeRate = transaction.exchangeRate
        adjustmentDirectionRawValue = transaction.adjustmentDirectionRawValue
        adjustmentReason = transaction.adjustmentReason
        merchantOrCounterparty = transaction.merchantOrCounterparty
        originalAmount = transaction.originalAmount
        discountAmount = transaction.discountAmount
        recognitionImportID = transaction.recognitionImportID
        bookID = transaction.bookID
        reimbursementStatusRawValue = transaction.reimbursementStatusRawValue
        sourceAccount = transaction.sourceAccount
        sourceWallet = transaction.sourceWallet
        destinationAccount = transaction.destinationAccount
        destinationWallet = transaction.destinationWallet
        feeWallet = transaction.feeWallet
        category = transaction.category
        tags = transaction.tags
        paymentParts = transaction.paymentParts
    }

    func restore() {
        transaction.typeRawValue = typeRawValue
        transaction.amount = amount
        transaction.currencyCode = currencyCode
        transaction.date = date
        transaction.note = note
        transaction.updatedAt = updatedAt
        transaction.sourceAmount = sourceAmount
        transaction.sourceCurrencyCode = sourceCurrencyCode
        transaction.destinationAmount = destinationAmount
        transaction.destinationCurrencyCode = destinationCurrencyCode
        transaction.feeAmount = feeAmount
        transaction.feeCurrencyCode = feeCurrencyCode
        transaction.exchangeRate = exchangeRate
        transaction.adjustmentDirectionRawValue = adjustmentDirectionRawValue
        transaction.adjustmentReason = adjustmentReason
        transaction.merchantOrCounterparty = merchantOrCounterparty
        transaction.originalAmount = originalAmount
        transaction.discountAmount = discountAmount
        transaction.recognitionImportID = recognitionImportID
        transaction.bookID = bookID
        transaction.reimbursementStatusRawValue = reimbursementStatusRawValue
        transaction.sourceAccount = sourceAccount
        transaction.sourceWallet = sourceWallet
        transaction.destinationAccount = destinationAccount
        transaction.destinationWallet = destinationWallet
        transaction.feeWallet = feeWallet
        transaction.category = category
        transaction.tags = tags
        transaction.paymentParts = paymentParts
    }
}
