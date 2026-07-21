import Foundation
import SwiftData

enum TransactionRelationError: LocalizedError, Equatable {
    case originalMustBeExpense
    case invalidAmount
    case exceedsOriginalAmount
    case currencyMismatch
    case aaConflict

    var errorDescription: String? {
        switch self {
        case .originalMustBeExpense: AppLocalization.string( "只有支出交易可以记录退款或报销")
        case .invalidAmount: AppLocalization.string( "金额必须大于 0")
        case .exceedsOriginalAmount: AppLocalization.string( "累计退款和报销不能超过原支出金额")
        case .currencyMismatch: AppLocalization.string( "退款或报销钱包必须与原交易币种一致")
        case .aaConflict: AppLocalization.string( "已设置 AA 的支出不能再记录退款或报销")
        }
    }
}

struct TransactionRelationSummary: Equatable {
    let refunded: Decimal
    let reimbursed: Decimal
    let originalAmount: Decimal

    var totalRecovered: Decimal { refunded + reimbursed }
    var remaining: Decimal { max(0, originalAmount - totalRecovered) }
}

@MainActor
final class TransactionRelationService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func relations(for original: LedgerTransaction) throws -> [TransactionRelation] {
        let id = original.id
        return try context.fetch(FetchDescriptor<TransactionRelation>())
            .filter { $0.originalTransactionID == id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func summary(for original: LedgerTransaction) throws -> TransactionRelationSummary {
        let relations = try relations(for: original)
        return TransactionRelationSummary(
            refunded: relations.filter { $0.kind == .refund }.reduce(0) { $0 + $1.amount },
            reimbursed: relations.filter { $0.kind == .reimbursement }.reduce(0) { $0 + $1.amount },
            originalAmount: original.sourceAmount ?? original.amount ?? 0
        )
    }

    @discardableResult
    func record(
        kind: TransactionRelationKind,
        original: LedgerTransaction,
        amount: Decimal,
        wallet: CurrencyWallet,
        date: Date = .now,
        note: String? = nil
    ) throws -> LedgerTransaction {
        guard original.type == .expense else {
            throw TransactionRelationError.originalMustBeExpense
        }
        let originalID = original.id
        let hasAASplit = try context.fetch(FetchDescriptor<AASplit>())
            .contains { $0.originalTransactionID == originalID }
        guard !hasAASplit else { throw TransactionRelationError.aaConflict }
        guard amount > 0 else { throw TransactionRelationError.invalidAmount }
        let originalCurrency = original.sourceCurrencyCode ?? original.currencyCode
        guard wallet.currencyCode == originalCurrency else {
            throw TransactionRelationError.currencyMismatch
        }
        let summary = try summary(for: original)
        guard amount <= summary.remaining else {
            throw TransactionRelationError.exceedsOriginalAmount
        }

        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookID = original.bookID else { throw LedgerError.missingBook }
        return try LedgerService(context: context).create(TransactionDraft(
            type: .income,
            amount: amount,
            sourceWallet: wallet,
            date: date,
            note: cleanNote?.isEmpty == false
                ? cleanNote
                : AppLocalization.string(
                    "关联\(kind.title)：\(original.note ?? original.merchantOrCounterparty ?? AppLocalization.string("原支出"))"
                ),
            merchantOrCounterparty: original.merchantOrCounterparty,
            category: nil
        ), bookID: bookID) { related in
            context.insert(TransactionRelation(
                kind: kind,
                originalTransactionID: original.id,
                relatedTransactionID: related.id,
                amount: amount
            ))
        }
    }
}
