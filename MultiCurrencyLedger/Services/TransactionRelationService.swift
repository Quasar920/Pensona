import Foundation
import SwiftData

enum TransactionRelationError: LocalizedError, Equatable {
    case originalMustBeExpense
    case invalidAmount
    case currencyMismatch
    case aaConflict
    case otherIncomeCategoryUnavailable
    case refundIncomeCategoryUnavailable

    var errorDescription: String? {
        switch self {
        case .originalMustBeExpense: AppLocalization.string( "只有支出交易可以记录退款或报销")
        case .invalidAmount: AppLocalization.string( "金额必须大于 0")
        case .currencyMismatch: AppLocalization.string( "退款或报销钱包必须与原交易币种一致")
        case .aaConflict: AppLocalization.string( "已设置 AA 的支出不能再记录退款或报销")
        case .otherIncomeCategoryUnavailable:
            AppLocalization.string( "找不到系统分类“其他收入 > 其他收入兜底”")
        case .refundIncomeCategoryUnavailable:
            AppLocalization.string( "找不到系统分类“其他收入 > 退款收入”")
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
            originalAmount: original.netExpenseAmount
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
        try LedgerBookAccess.requireActiveBook(in: context, for: original)
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
        let recoveryAmount = min(amount, summary.remaining)
        let excessIncomeAmount = amount - recoveryAmount
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookID = original.bookID else { throw LedgerError.missingBook }
        let relationNote = cleanNote?.isEmpty == false
            ? cleanNote
            : AppLocalization.string(
                "关联\(kind.title)：\(original.note ?? original.merchantOrCounterparty ?? AppLocalization.string("原支出"))"
            )

        // A refund deposit always records exactly the amount the person
        // received. Only `recoveryAmount` offsets the original expense; the
        // remainder is represented by the relation as refund income, without
        // a second wallet credit.
        if kind == .refund {
            return try LedgerService(context: context).create(TransactionDraft(
                type: .income,
                amount: amount,
                sourceWallet: wallet,
                date: date,
                note: relationNote,
                merchantOrCounterparty: TransactionSystemPresentation.refundDepositTitleMarker,
                category: nil
            ), bookID: bookID) { related in
                context.insert(TransactionRelation(
                    kind: .refund,
                    originalTransactionID: original.id,
                    relatedTransactionID: related.id,
                    amount: recoveryAmount,
                    excessIncomeAmount: excessIncomeAmount > 0 ? excessIncomeAmount : nil
                ))
            }
        }

        if excessIncomeAmount == 0 {
            return try LedgerService(context: context).create(TransactionDraft(
                type: .income,
                amount: recoveryAmount,
                sourceWallet: wallet,
                date: date,
                note: relationNote,
                merchantOrCounterparty: kind == .refund
                    ? TransactionSystemPresentation.refundDepositTitleMarker
                    : original.merchantOrCounterparty,
                category: nil
            ), bookID: bookID) { related in
                context.insert(TransactionRelation(
                    kind: kind,
                    originalTransactionID: original.id,
                    relatedTransactionID: related.id,
                    amount: recoveryAmount
                ))
            }
        }

        let excessIncomeCategory = try excessIncomeCategory(for: kind)
        let excessTitle = kind == .refund ? AppLocalization.string("退款收入") : AppLocalization.string("其他收入")
        let excessNote = cleanNote?.isEmpty == false
            ? "\(cleanNote!)（超额部分自动记为\(excessTitle)）"
            : AppLocalization.string(
                "关联\(kind.title)超额\(excessTitle)：\(original.note ?? original.merchantOrCounterparty ?? AppLocalization.string("原支出"))"
            )
        var drafts: [TransactionDraft] = []
        if recoveryAmount > 0 {
            drafts.append(TransactionDraft(
                type: .income,
                amount: recoveryAmount,
                sourceWallet: wallet,
                date: date,
                note: relationNote,
                merchantOrCounterparty: kind == .refund
                    ? TransactionSystemPresentation.refundDepositTitleMarker
                    : original.merchantOrCounterparty,
                category: nil
            ))
        }
        drafts.append(TransactionDraft(
            type: .income,
            amount: excessIncomeAmount,
            sourceWallet: wallet,
            date: date,
            note: excessNote,
            merchantOrCounterparty: original.merchantOrCounterparty,
            category: excessIncomeCategory
        ))

        let transactions = try LedgerService(context: context).createBatch(drafts, bookID: bookID) { created in
            let related = recoveryAmount > 0 ? created[0] : created[created.count - 1]
            let excess = created[created.count - 1]
            context.insert(TransactionRelation(
                kind: kind,
                originalTransactionID: original.id,
                relatedTransactionID: related.id,
                amount: recoveryAmount,
                excessIncomeTransactionID: excess.id,
                excessIncomeAmount: excessIncomeAmount
            ))
        }
        return transactions[0]
    }

    private func excessIncomeCategory(for kind: TransactionRelationKind) throws -> LedgerCategory {
        let key = kind == .refund
            ? "category.income.other.refund-income"
            : "category.income.other.fallback"
        guard let category = try context.fetch(FetchDescriptor<LedgerCategory>()).first(where: {
            $0.type == .income && !$0.isArchived && $0.systemLocalizationKey == key
        }) else {
            throw kind == .refund
                ? TransactionRelationError.refundIncomeCategoryUnavailable
                : TransactionRelationError.otherIncomeCategoryUnavailable
        }
        return category
    }
}
