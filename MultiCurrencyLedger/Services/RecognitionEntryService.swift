import Foundation
import SwiftData

enum RecognitionEntryError: LocalizedError, Equatable {
    case unsupportedType
    case feeRequiresManualEntry
    case invalidAmount
    case walletCurrencyMismatch
    case categoryTypeMismatch
    case missingBook

    var errorDescription: String? {
        switch self {
        case .unsupportedType: "当前识别类型需要使用专门的转账或换汇确认流程"
        case .feeRequiresManualEntry: "含手续费的交易需要手动确认手续费归属"
        case .invalidAmount: "确认金额必须大于 0"
        case .walletCurrencyMismatch: "所选钱包与交易币种不一致"
        case .categoryTypeMismatch: "所选分类与交易类型不一致"
        case .missingBook: "识别交易必须归属一个账本"
        }
    }
}

@MainActor
final class RecognitionEntryService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func confirm(
        _ draft: RecognitionConfirmationDraft,
        wallet: CurrencyWallet,
        category: LedgerCategory?,
        importRecord: RecognitionImportRecord? = nil,
        importStatus: RecognitionImportStatus = .confirmed
    ) throws -> LedgerTransaction {
        guard draft.type == .expense || draft.type == .income else {
            throw RecognitionEntryError.unsupportedType
        }
        guard draft.feeAmount == 0 else { throw RecognitionEntryError.feeRequiresManualEntry }
        guard draft.paidAmount > 0 else { throw RecognitionEntryError.invalidAmount }
        guard wallet.currencyCode == draft.currency.rawValue else {
            throw RecognitionEntryError.walletCurrencyMismatch
        }
        if let category {
            let expected: CategoryKind = draft.type == .expense ? .expense : .income
            guard category.type == expected else { throw RecognitionEntryError.categoryTypeMismatch }
        }
        guard let bookID = wallet.account?.book?.id else { throw RecognitionEntryError.missingBook }

        let transaction = LedgerTransaction(
            type: draft.type == .expense ? .expense : .income,
            amount: draft.paidAmount,
            currencyCode: draft.currency.rawValue,
            date: draft.occurredAt,
            note: draft.noteForPersistence,
            sourceAccount: wallet.account,
            sourceWallet: wallet,
            sourceAmount: draft.paidAmount,
            sourceCurrencyCode: draft.currency.rawValue,
            category: category,
            merchantOrCounterparty: draft.merchantForPersistence,
            originalAmount: draft.originalAmount,
            discountAmount: draft.discountAmount
        )
        let record = importRecord ?? RecognitionImportRecordFactory.make(
            draft: draft,
            status: importStatus,
            bookID: bookID,
            selectedWalletID: wallet.id,
            selectedCategoryID: category?.id
        )
        record.statusRawValue = importStatus.rawValue
        record.selectedWalletID = wallet.id
        record.selectedCategoryID = category?.id
        return try LedgerService(context: context).persistRecognized(transaction, importRecord: record)
    }
}
