import Foundation
import SwiftData

enum AASplitError: LocalizedError, Equatable {
    case expenseRequired
    case invalidOtherPeopleCount
    case invalidOthersOwedAmount
    case customAmountNeedsConfirmation
    case collectedAmountExceedsOwed
    case settlementAmountInvalid
    case settlementExceedsRemaining
    case walletUnavailable
    case currencyMismatch
    case bookMismatch
    case conflictingRecovery
    case settlementsMustBeRemovedFirst
    case recoveryTransactionMissing

    var errorDescription: String? {
        switch self {
        case .expenseRequired: AppLocalization.string( "只有支出可以设置 AA 分摊")
        case .invalidOtherPeopleCount: AppLocalization.string( "请填写大于 0 的其他人数")
        case .invalidOthersOwedAmount: AppLocalization.string( "其他人应还金额必须大于 0，且不能超过本次实付")
        case .customAmountNeedsConfirmation: AppLocalization.string( "支出金额已变化，请重新确认 AA 的自定义金额")
        case .collectedAmountExceedsOwed: AppLocalization.string( "其他人应还金额不能低于已经收到的金额")
        case .settlementAmountInvalid: AppLocalization.string( "收款金额必须大于 0")
        case .settlementExceedsRemaining: AppLocalization.string( "收款金额不能超过剩余待收")
        case .walletUnavailable: AppLocalization.string( "请选择可用的收款账户")
        case .currencyMismatch: AppLocalization.string( "AA 收款账户必须与原支出币种一致")
        case .bookMismatch: AppLocalization.string( "AA 收款账户必须与原支出属于同一账本")
        case .conflictingRecovery: AppLocalization.string( "已有退款或报销的支出不能设置 AA")
        case .settlementsMustBeRemovedFirst: AppLocalization.string( "请先删除这笔 AA 的收款记录")
        case .recoveryTransactionMissing: AppLocalization.string( "找不到对应的 AA 收款流水")
        }
    }
}

struct AASplitCalculator {
    func amounts(
        totalAmount: Decimal,
        otherPeopleCount: Int,
        mode: AASplitCalculationMode,
        customOthersOwedAmount: Decimal,
        currencyCode: String
    ) throws -> AASplitAmounts {
        guard totalAmount > 0 else { throw AASplitError.invalidOthersOwedAmount }
        guard otherPeopleCount > 0 else { throw AASplitError.invalidOtherPeopleCount }

        let othersOwed: Decimal
        switch mode {
        case .equal:
            let people = Decimal(otherPeopleCount + 1)
            let perPerson = roundedDown(
                totalAmount / people,
                scale: SupportedCurrency.fractionDigits(for: currencyCode)
            )
            othersOwed = perPerson * Decimal(otherPeopleCount)
        case .custom:
            othersOwed = customOthersOwedAmount
        }

        guard othersOwed > 0, othersOwed <= totalAmount else {
            throw AASplitError.invalidOthersOwedAmount
        }
        return AASplitAmounts(
            totalAmount: totalAmount,
            othersOwedAmount: othersOwed,
            myShareAmount: totalAmount - othersOwed
        )
    }

    func resolvedDraft(
        _ draft: AASplitDraft,
        totalAmount: Decimal,
        currencyCode: String
    ) throws -> AASplitDraft {
        if draft.calculationMode == .custom, draft.basedOnAmount != totalAmount {
            throw AASplitError.customAmountNeedsConfirmation
        }
        let result = try amounts(
            totalAmount: totalAmount,
            otherPeopleCount: draft.otherPeopleCount,
            mode: draft.calculationMode,
            customOthersOwedAmount: draft.othersOwedAmount,
            currencyCode: currencyCode
        )
        var resolved = draft
        resolved.othersOwedAmount = result.othersOwedAmount
        resolved.basedOnAmount = totalAmount
        let cleanNote = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        resolved.note = cleanNote?.isEmpty == false ? cleanNote : nil
        return resolved
    }

    private func roundedDown(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal.zero
        NSDecimalRound(&result, &source, scale, .down)
        return result
    }
}

struct AAReceivableItem: Identifiable {
    let split: AASplit
    let transaction: LedgerTransaction
    let summary: AASplitSummary
    var id: UUID { split.id }
}

struct AAReceivableOverview: Equatable {
    let amount: Decimal
    let openCount: Int
    let missingCodes: Set<String>
}

struct AAQueryService {
    func summary(for split: AASplit, settlements: [AASettlement]) -> AASplitSummary {
        let collected = settlements
            .filter { $0.splitID == split.id }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return AASplitSummary(
            othersOwedAmount: split.othersOwedAmount,
            collectedAmount: collected
        )
    }

    func items(
        splits: [AASplit],
        settlements: [AASettlement],
        transactions: [LedgerTransaction],
        bookID: UUID?
    ) -> [AAReceivableItem] {
        let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        return splits.compactMap { split in
            guard let transaction = transactionByID[split.originalTransactionID],
                  bookID == nil || transaction.bookID == bookID else { return nil }
            return AAReceivableItem(
                split: split,
                transaction: transaction,
                summary: summary(for: split, settlements: settlements)
            )
        }
        .sorted { $0.transaction.date > $1.transaction.date }
    }

    func overview(
        items: [AAReceivableItem],
        baseCurrencyCode: String,
        rates: [ExchangeRate]
    ) -> AAReceivableOverview {
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        var total = Decimal.zero
        var missing = Set<String>()
        let openItems = items.filter { $0.summary.remainingAmount > 0 }
        for item in openItems {
            let code = item.transaction.sourceCurrencyCode
                ?? item.transaction.currencyCode
                ?? baseCurrencyCode
            if let value = valuation.value(item.summary.remainingAmount, currencyCode: code) {
                total += value
            } else {
                missing.insert(code)
            }
        }
        return AAReceivableOverview(
            amount: total,
            openCount: openItems.count,
            missingCodes: missing
        )
    }
}

@MainActor
final class AASplitService {
    private let context: ModelContext
    private let calculator = AASplitCalculator()

    init(context: ModelContext) {
        self.context = context
    }

    func split(for transaction: LedgerTransaction) throws -> AASplit? {
        let id = transaction.id
        return try context.fetch(FetchDescriptor<AASplit>())
            .first { $0.originalTransactionID == id }
    }

    func settlements(for split: AASplit) throws -> [AASettlement] {
        let id = split.id
        return try context.fetch(FetchDescriptor<AASettlement>())
            .filter { $0.splitID == id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func upsert(
        _ draft: AASplitDraft,
        for transaction: LedgerTransaction,
        save: Bool = true
    ) throws -> AASplit {
        try LedgerBookAccess.requireActiveBook(in: context, for: transaction)
        guard transaction.type == .expense else { throw AASplitError.expenseRequired }
        let transactionID = transaction.id
        let relations = try context.fetch(FetchDescriptor<TransactionRelation>())
        guard !relations.contains(where: { $0.originalTransactionID == transactionID }) else {
            throw AASplitError.conflictingRecovery
        }
        let total = transaction.sourceAmount ?? transaction.amount ?? 0
        let currencyCode = transaction.sourceCurrencyCode
            ?? transaction.currencyCode
            ?? SupportedCurrency.CNY.rawValue
        let resolved = try calculator.resolvedDraft(
            draft,
            totalAmount: total,
            currencyCode: currencyCode
        )
        let existing = try split(for: transaction)
        if let existing {
            let existingSettlements = try settlements(for: existing)
            let collected = existingSettlements.reduce(Decimal.zero) { $0 + $1.amount }
            guard resolved.othersOwedAmount >= collected else {
                throw AASplitError.collectedAmountExceedsOwed
            }
            if !existingSettlements.isEmpty {
                let recoveryIDs = Set(existingSettlements.map(\.recoveryTransactionID))
                let recoveries = try context.fetch(FetchDescriptor<LedgerTransaction>())
                    .filter { recoveryIDs.contains($0.id) }
                guard recoveries.count == recoveryIDs.count else {
                    throw AASplitError.recoveryTransactionMissing
                }
                let originalBookID = transaction.bookID
                guard recoveries.allSatisfy({ $0.bookID == originalBookID }) else {
                    throw AASplitError.bookMismatch
                }
                guard recoveries.allSatisfy({
                    ($0.sourceCurrencyCode ?? $0.currencyCode) == currencyCode
                }) else {
                    throw AASplitError.currencyMismatch
                }
            }
            existing.otherPeopleCount = resolved.otherPeopleCount
            existing.calculationModeRawValue = resolved.calculationMode.rawValue
            existing.othersOwedAmount = resolved.othersOwedAmount
            existing.note = resolved.note
            existing.updatedAt = .now
            if save { try persist() }
            return existing
        }

        let split = AASplit(
            originalTransactionID: transaction.id,
            otherPeopleCount: resolved.otherPeopleCount,
            calculationMode: resolved.calculationMode,
            othersOwedAmount: resolved.othersOwedAmount,
            note: resolved.note
        )
        context.insert(split)
        if save { try persist() }
        return split
    }

    func remove(from transaction: LedgerTransaction, save: Bool = true) throws {
        try LedgerBookAccess.requireActiveBook(in: context, for: transaction)
        guard let split = try split(for: transaction) else { return }
        guard try settlements(for: split).isEmpty else {
            throw AASplitError.settlementsMustBeRemovedFirst
        }
        context.delete(split)
        if save { try persist() }
    }

    private func persist() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
final class AASettlementService {
    private let context: ModelContext
    private let queryService = AAQueryService()

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func record(
        split: AASplit,
        original: LedgerTransaction,
        amount: Decimal,
        wallet: CurrencyWallet,
        date: Date,
        note: String?
    ) throws -> LedgerTransaction {
        try LedgerBookAccess.requireActiveBook(in: context, for: original)
        guard amount > 0 else { throw AASplitError.settlementAmountInvalid }
        guard wallet.isEnabled, wallet.account?.isArchived == false else {
            throw AASplitError.walletUnavailable
        }
        guard let originalBookID = original.bookID else { throw LedgerError.missingBook }
        let originalCode = original.sourceCurrencyCode ?? original.currencyCode
        guard wallet.currencyCode == originalCode else { throw AASplitError.currencyMismatch }

        let settlements = try context.fetch(FetchDescriptor<AASettlement>())
        let summary = queryService.summary(for: split, settlements: settlements)
        guard amount <= summary.remainingAmount else { throw AASplitError.settlementExceedsRemaining }

        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try LedgerService(context: context).create(TransactionDraft(
            type: .income,
            amount: amount,
            sourceWallet: wallet,
            date: date,
            note: cleanNote?.isEmpty == false ? cleanNote : nil,
            merchantOrCounterparty: "AA 收回",
            category: nil
        ), bookID: originalBookID) { recovery in
            context.insert(AASettlement(
                splitID: split.id,
                recoveryTransactionID: recovery.id,
                amount: amount
            ))
        }
    }

    func delete(_ settlement: AASettlement) throws {
        let recoveryID = settlement.recoveryTransactionID
        guard let recovery = try context.fetch(FetchDescriptor<LedgerTransaction>())
            .first(where: { $0.id == recoveryID }) else {
            throw AASplitError.recoveryTransactionMissing
        }
        try LedgerService(context: context).deleteAASettlementTransaction(
            recovery,
            settlement: settlement
        )
    }
}
