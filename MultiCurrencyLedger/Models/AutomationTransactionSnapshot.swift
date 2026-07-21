import Foundation

enum AutomationDraftError: LocalizedError, Equatable {
    case missingBook
    case crossBookReference
    case invalidReference
    case corruptSnapshot

    var errorDescription: String? {
        switch self {
        case .missingBook: AppLocalization.string( "自动记账规则必须归属一个账本")
        case .crossBookReference: AppLocalization.string( "自动记账规则不能引用其他账本的钱包或分类")
        case .invalidReference: AppLocalization.string( "自动记账规则引用的钱包或分类已失效")
        case .corruptSnapshot: AppLocalization.string( "自动记账规则的数据已损坏，请重新创建")
        }
    }
}

struct AutomationPaymentPartSnapshot: Codable, Equatable {
    let walletID: UUID
    let amount: Decimal
}

/// A stable, model-independent copy of a transaction draft. Automation rules
/// store IDs rather than SwiftData relationships so archiving a referenced
/// object cannot silently redirect future entries.
struct AutomationTransactionSnapshot: Codable, Equatable {
    let type: TransactionKind
    let amount: Decimal
    let sourceWalletID: UUID
    let destinationWalletID: UUID?
    let destinationAmount: Decimal?
    let feeAmount: Decimal?
    let feeWalletID: UUID?
    let categoryID: UUID?
    let paymentParts: [AutomationPaymentPartSnapshot]
    let note: String?
    let merchantOrCounterparty: String?
    let adjustmentDirection: AdjustmentDirection?
    let adjustmentReason: String?

    init(draft: TransactionDraft) throws {
        guard let sourceWallet = draft.sourceWallet,
              sourceWallet.isEnabled,
              sourceWallet.account?.isArchived == false else {
            throw AutomationDraftError.invalidReference
        }
        self.type = draft.type
        amount = draft.amount
        sourceWalletID = sourceWallet.id
        destinationWalletID = draft.destinationWallet?.id
        destinationAmount = draft.destinationAmount
        feeAmount = draft.feeAmount
        feeWalletID = draft.feeWallet?.id
        categoryID = draft.category?.id
        paymentParts = draft.paymentParts.map {
            AutomationPaymentPartSnapshot(walletID: $0.wallet.id, amount: $0.amount)
        }
        note = draft.note
        merchantOrCounterparty = draft.merchantOrCounterparty
        adjustmentDirection = draft.adjustmentDirection
        adjustmentReason = draft.adjustmentReason
    }
}

struct AutomationDraftCodec {
    func encode(_ draft: TransactionDraft, bookID: UUID) throws -> (bookID: UUID, data: Data) {
        guard let sourceWallet = draft.sourceWallet,
              sourceWallet.isEnabled,
              sourceWallet.account?.isArchived == false else {
            throw AutomationDraftError.missingBook
        }
        return (bookID, try JSONEncoder().encode(AutomationTransactionSnapshot(draft: draft)))
    }

    func resolve(
        data: Data,
        bookID: UUID,
        date: Date,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory]
    ) throws -> TransactionDraft {
        guard let snapshot = try? JSONDecoder().decode(AutomationTransactionSnapshot.self, from: data) else {
            throw AutomationDraftError.corruptSnapshot
        }
        let scopedWallets = wallets.filter {
            $0.isEnabled && $0.account?.isArchived == false
        }
        guard let source = scopedWallets.first(where: { $0.id == snapshot.sourceWalletID }) else {
            throw AutomationDraftError.invalidReference
        }
        let destination = snapshot.destinationWalletID.flatMap { id in
            scopedWallets.first { $0.id == id }
        }
        let feeWallet = snapshot.feeWalletID.flatMap { id in
            scopedWallets.first { $0.id == id }
        }
        let category = snapshot.categoryID.flatMap { id in
            categories.first {
                $0.id == id && !$0.isArchived
            }
        }
        let paymentParts = snapshot.paymentParts.compactMap { part in
            scopedWallets.first(where: { $0.id == part.walletID }).map {
                TransactionPaymentPartDraft(wallet: $0, amount: part.amount)
            }
        }

        guard (snapshot.destinationWalletID == nil || destination != nil),
              (snapshot.feeWalletID == nil || feeWallet != nil),
              (snapshot.categoryID == nil || category != nil),
              paymentParts.count == snapshot.paymentParts.count else {
            throw AutomationDraftError.invalidReference
        }

        return TransactionDraft(
            type: snapshot.type,
            bookID: bookID,
            amount: snapshot.amount,
            sourceWallet: source,
            destinationWallet: destination,
            destinationAmount: snapshot.destinationAmount,
            feeAmount: snapshot.feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: snapshot.note,
            merchantOrCounterparty: snapshot.merchantOrCounterparty,
            category: category,
            paymentParts: paymentParts,
            adjustmentDirection: snapshot.adjustmentDirection,
            adjustmentReason: snapshot.adjustmentReason
        )
    }
}
