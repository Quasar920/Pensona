import Foundation

/// Editable, UI-friendly state shared by create, edit and copy flows.
struct TransactionFormState {
    var kind: TransactionKind
    var amountText: String
    var destinationAmountText: String
    var sourceWalletID: UUID?
    var destinationWalletID: UUID?
    var categoryID: UUID?
    var feeWalletID: UUID?
    var date: Date
    var note: String
    var merchantOrCounterparty: String
    var adjustmentDirection: AdjustmentDirection
    var adjustmentReason: String
    var includesFee: Bool
    var feeText: String

    private var originalAmount: Decimal?
    private var discountAmount: Decimal?
    private var recognitionImportID: UUID?

    init(kind: TransactionKind = .expense, date: Date = .now) {
        self.kind = kind
        amountText = ""
        destinationAmountText = ""
        sourceWalletID = nil
        destinationWalletID = nil
        categoryID = nil
        feeWalletID = nil
        self.date = date
        note = ""
        merchantOrCounterparty = ""
        adjustmentDirection = .increase
        adjustmentReason = "手动校准"
        includesFee = false
        feeText = ""
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    init(draft: TransactionDraft) {
        kind = draft.type
        amountText = Self.string(draft.amount)
        destinationAmountText = draft.destinationAmount.map(Self.string) ?? ""
        sourceWalletID = draft.sourceWallet?.id
        destinationWalletID = draft.destinationWallet?.id
        categoryID = draft.category?.id
        feeWalletID = draft.feeWallet?.id
        date = draft.date
        note = draft.note ?? ""
        merchantOrCounterparty = draft.merchantOrCounterparty ?? ""
        adjustmentDirection = draft.adjustmentDirection ?? .increase
        adjustmentReason = draft.adjustmentReason ?? "手动校准"
        includesFee = draft.feeAmount != nil
        feeText = draft.feeAmount.map(Self.string) ?? ""
        originalAmount = draft.originalAmount
        discountAmount = draft.discountAmount
        recognitionImportID = draft.recognitionImportID
    }

    init(transaction: LedgerTransaction) {
        self.init(draft: TransactionDraft(transaction: transaction))
    }

    mutating func prepareForKindChange() {
        categoryID = nil
        destinationWalletID = nil
        feeWalletID = nil
        destinationAmountText = ""
        includesFee = false
        feeText = ""
        adjustmentDirection = .increase
        adjustmentReason = "手动校准"
    }

    mutating func resetForContinuousEntry(now: Date = .now) {
        amountText = ""
        destinationAmountText = ""
        feeText = ""
        includesFee = false
        feeWalletID = sourceWalletID
        date = now
        note = ""
        merchantOrCounterparty = ""
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    mutating func removeImportedMetadataForCopy(now: Date = .now) {
        date = now
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    func makeDraft(
        wallets: [CurrencyWallet],
        categories: [LedgerCategory]
    ) throws -> TransactionDraft {
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            throw ValidationError("请输入大于 0 的有效金额")
        }
        guard let sourceWallet = wallets.first(where: { $0.id == sourceWalletID }) else {
            throw ValidationError("请选择来源钱包")
        }

        let isMovement = kind == .transfer || kind == .exchange
        let destinationWallet = isMovement
            ? wallets.first(where: { $0.id == destinationWalletID })
            : nil
        if isMovement, destinationWallet == nil {
            throw ValidationError("请选择目标钱包")
        }

        let destinationAmount: Decimal?
        switch kind {
        case .transfer:
            destinationAmount = amount
        case .exchange:
            guard let parsed = DecimalParser.parse(destinationAmountText), parsed > 0 else {
                throw ValidationError("请输入大于 0 的换入金额")
            }
            destinationAmount = parsed
        default:
            destinationAmount = nil
        }

        let feeAmount: Decimal?
        let feeWallet: CurrencyWallet?
        if isMovement, includesFee {
            guard let parsed = DecimalParser.parse(feeText), parsed > 0 else {
                throw ValidationError("请输入大于 0 的手续费")
            }
            guard let selectedFeeWallet = wallets.first(where: { $0.id == feeWalletID }) else {
                throw ValidationError("请选择手续费钱包")
            }
            feeAmount = parsed
            feeWallet = selectedFeeWallet
        } else {
            feeAmount = nil
            feeWallet = nil
        }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMerchant = merchantOrCounterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAdjustmentReason = adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines)

        return TransactionDraft(
            type: kind,
            amount: amount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            destinationAmount: destinationAmount,
            feeAmount: feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: cleanNote.isEmpty ? nil : cleanNote,
            merchantOrCounterparty: cleanMerchant.isEmpty ? nil : cleanMerchant,
            category: categories.first(where: { $0.id == categoryID }),
            adjustmentDirection: kind == .adjustment ? adjustmentDirection : nil,
            adjustmentReason: kind == .adjustment
                ? (cleanAdjustmentReason.isEmpty ? "手动校准" : cleanAdjustmentReason)
                : nil,
            originalAmount: originalAmount,
            discountAmount: discountAmount,
            recognitionImportID: recognitionImportID
        )
    }

    private static func string(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}
