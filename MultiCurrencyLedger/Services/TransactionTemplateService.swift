import Foundation
import SwiftData

enum TransactionTemplateError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case missingBook
    case invalidReference

    var errorDescription: String? {
        switch self {
        case .emptyName: AppLocalization.string( "请输入模板名称")
        case .duplicateName: AppLocalization.string( "当前账本已存在同名模板")
        case .missingBook: AppLocalization.string( "模板必须归属一个账本")
        case .invalidReference: AppLocalization.string( "模板引用的钱包或分类已失效，请编辑或重新创建模板")
        }
    }
}

@MainActor
final class TransactionTemplateService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func scoped(bookID: UUID, includeArchived: Bool = false) throws -> [TransactionTemplate] {
        try context.fetch(FetchDescriptor<TransactionTemplate>())
            .filter { $0.bookID == bookID && (includeArchived || !$0.isArchived) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create(name: String, bookID: UUID, from draft: TransactionDraft) throws -> TransactionTemplate {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw TransactionTemplateError.emptyName }
        guard let sourceWallet = draft.sourceWallet,
              sourceWallet.isEnabled,
              sourceWallet.account?.isArchived == false else {
            throw TransactionTemplateError.missingBook
        }
        let duplicate = try scoped(bookID: bookID, includeArchived: true).contains {
            $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicate else { throw TransactionTemplateError.duplicateName }
        let template = TransactionTemplate(
            name: cleanName,
            bookID: bookID,
            type: draft.type,
            amount: draft.amount,
            sourceWalletID: sourceWallet.id,
            destinationWalletID: draft.destinationWallet?.id,
            destinationAmount: draft.destinationAmount,
            feeAmount: draft.feeAmount,
            feeWalletID: draft.feeWallet?.id,
            categoryID: draft.category?.id,
            paymentParts: draft.paymentParts.map {
                TemplatePaymentPartReference(walletID: $0.wallet.id, amount: $0.amount)
            },
            note: draft.note,
            merchantOrCounterparty: draft.merchantOrCounterparty,
            adjustmentDirection: draft.adjustmentDirection,
            adjustmentReason: draft.adjustmentReason
        )
        context.insert(template)
        try context.save()
        return template
    }

    func resolve(
        _ template: TransactionTemplate,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory],
        date: Date = .now
    ) throws -> TransactionDraft {
        guard !template.isArchived,
              let source = wallets.first(where: { $0.id == template.sourceWalletID }),
              source.isEnabled,
              source.account?.isArchived == false else {
            throw TransactionTemplateError.invalidReference
        }
        let scopedWallets = wallets.filter {
            $0.isEnabled && $0.account?.isArchived == false
        }
        let destination = template.destinationWalletID.flatMap { id in scopedWallets.first { $0.id == id } }
        let feeWallet = template.feeWalletID.flatMap { id in scopedWallets.first { $0.id == id } }
        let category = template.categoryID.flatMap { id in
            categories.first {
                $0.id == id && !$0.isArchived
            }
        }
        let resolvedPaymentParts = template.paymentPartReferences.compactMap { reference in
            scopedWallets.first(where: { $0.id == reference.walletID }).map {
                TransactionPaymentPartDraft(wallet: $0, amount: reference.amount)
            }
        }

        if template.destinationWalletID != nil && destination == nil
            || template.feeWalletID != nil && feeWallet == nil
            || template.categoryID != nil && category == nil {
            throw TransactionTemplateError.invalidReference
        }
        if resolvedPaymentParts.count != template.paymentPartReferences.count {
            throw TransactionTemplateError.invalidReference
        }

        return TransactionDraft(
            type: template.type,
            bookID: template.bookID,
            amount: template.amount,
            sourceWallet: source,
            destinationWallet: destination,
            destinationAmount: template.destinationAmount,
            feeAmount: template.feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: template.note,
            merchantOrCounterparty: template.merchantOrCounterparty,
            category: category,
            paymentParts: resolvedPaymentParts,
            adjustmentDirection: template.adjustmentDirection,
            adjustmentReason: template.adjustmentReason
        )
    }

    func setArchived(_ archived: Bool, template: TransactionTemplate) throws {
        template.isArchived = archived
        template.updatedAt = .now
        try context.save()
    }

    func delete(_ template: TransactionTemplate) throws {
        context.delete(template)
        try context.save()
    }
}
