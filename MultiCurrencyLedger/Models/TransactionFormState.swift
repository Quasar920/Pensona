import Foundation

/// Editable, UI-friendly state shared by create, edit and copy flows.
struct TransactionFormState {
    var kind: TransactionKind
    var amountText: String
    var destinationAmountText: String
    var exchangeRateText: String
    var sourceWalletID: UUID?
    var destinationWalletID: UUID?
    var categoryID: UUID?
    var feeWalletID: UUID?
    var date: Date
    var note: String
    var merchantOrCounterparty: String
    var adjustmentDirection: AdjustmentDirection
    var adjustmentInputMode: AdjustmentInputMode
    var adjustmentReason: String
    var reimbursementStatus: ReimbursementStatus
    var includesFee: Bool
    var feeText: String
    var usesSplitPayment: Bool
    var paymentParts: [PaymentPartFormState]
    var aaSplitDraft: AASplitDraft?

    private var originalAmount: Decimal?
    private var discountAmount: Decimal?
    private var recognitionImportID: UUID?

    var hasUserEnteredContent: Bool {
        !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !destinationAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !exchangeRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !merchantOrCounterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (includesFee && !feeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || paymentParts.contains { !$0.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || aaSplitDraft != nil
            || reimbursementStatus == .pending
    }

    init(kind: TransactionKind = .expense, date: Date = .now) {
        self.kind = kind
        amountText = ""
        destinationAmountText = ""
        exchangeRateText = ""
        sourceWalletID = nil
        destinationWalletID = nil
        categoryID = nil
        feeWalletID = nil
        self.date = date
        note = ""
        merchantOrCounterparty = ""
        adjustmentDirection = .increase
        adjustmentInputMode = .delta
        adjustmentReason = "手动校准"
        reimbursementStatus = .none
        includesFee = false
        feeText = ""
        usesSplitPayment = false
        paymentParts = []
        aaSplitDraft = nil
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    init(draft: TransactionDraft) {
        kind = draft.type
        amountText = Self.string(draft.amount)
        destinationAmountText = draft.destinationAmount.map(Self.string) ?? ""
        if draft.type == .exchange, draft.amount > 0, let destinationAmount = draft.destinationAmount {
            exchangeRateText = Self.string(destinationAmount / draft.amount)
        } else {
            exchangeRateText = ""
        }
        sourceWalletID = draft.sourceWallet?.id
        destinationWalletID = draft.destinationWallet?.id
        categoryID = draft.category?.id
        feeWalletID = draft.feeWallet?.id
        date = draft.date
        note = draft.note ?? ""
        merchantOrCounterparty = draft.merchantOrCounterparty ?? ""
        adjustmentDirection = draft.adjustmentDirection ?? .increase
        adjustmentInputMode = .delta
        adjustmentReason = draft.adjustmentReason ?? "手动校准"
        reimbursementStatus = draft.reimbursementStatus
        includesFee = draft.feeAmount != nil
        feeText = draft.feeAmount.map(Self.string) ?? ""
        usesSplitPayment = draft.paymentParts.count >= 2
        paymentParts = draft.paymentParts.map {
            PaymentPartFormState(walletID: $0.wallet.id, amountText: Self.string($0.amount))
        }
        aaSplitDraft = nil
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
        exchangeRateText = ""
        includesFee = false
        feeText = ""
        adjustmentDirection = .increase
        adjustmentInputMode = .delta
        adjustmentReason = "手动校准"
        reimbursementStatus = .none
        usesSplitPayment = false
        paymentParts = []
        aaSplitDraft = nil
    }

    mutating func resetForContinuousEntry(now _: Date = .now) {
        amountText = ""
        destinationAmountText = ""
        exchangeRateText = ""
        categoryID = nil
        feeText = ""
        includesFee = false
        feeWalletID = sourceWalletID
        note = ""
        merchantOrCounterparty = ""
        for index in paymentParts.indices { paymentParts[index].amountText = "" }
        aaSplitDraft = nil
        reimbursementStatus = .none
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    mutating func removeImportedMetadataForCopy(now: Date = .now) {
        date = now
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
        aaSplitDraft = nil
    }

    func makeDraft(
        wallets: [CurrencyWallet],
        categories: [LedgerCategory]
    ) throws -> TransactionDraft {
        guard let sourceWallet = wallets.first(where: { $0.id == sourceWalletID }) else {
            throw ValidationError("请选择来源钱包")
        }
        guard let enteredAmount = DecimalParser.parse(amountText), enteredAmount >= 0 else {
            throw ValidationError("请输入大于 0 的有效金额")
        }

        let amount: Decimal
        let resolvedAdjustmentDirection: AdjustmentDirection
        if kind == .adjustment, adjustmentInputMode == .finalBalance {
            let difference = enteredAmount - sourceWallet.balance
            guard difference != 0 else { throw ValidationError("最终余额必须与当前余额不同") }
            amount = abs(difference)
            resolvedAdjustmentDirection = difference > 0 ? .increase : .decrease
        } else {
            guard enteredAmount > 0 else { throw ValidationError("请输入大于 0 的有效金额") }
            amount = enteredAmount
            resolvedAdjustmentDirection = adjustmentDirection
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

        let resolvedPaymentParts: [TransactionPaymentPartDraft]
        if usesSplitPayment {
            guard kind == .expense || kind == .income, paymentParts.count >= 2 else {
                throw LedgerError.paymentPartsMismatch
            }
            resolvedPaymentParts = try paymentParts.map { part in
                guard let wallet = wallets.first(where: { $0.id == part.walletID }),
                      let amount = DecimalParser.parse(part.amountText), amount > 0 else {
                    throw LedgerError.paymentPartsMismatch
                }
                return TransactionPaymentPartDraft(wallet: wallet, amount: amount)
            }
        } else {
            resolvedPaymentParts = []
        }

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
            paymentParts: resolvedPaymentParts,
            adjustmentDirection: kind == .adjustment ? resolvedAdjustmentDirection : nil,
            adjustmentReason: kind == .adjustment
                ? (cleanAdjustmentReason.isEmpty ? "手动校准" : cleanAdjustmentReason)
                : nil,
            originalAmount: originalAmount,
            discountAmount: discountAmount,
            recognitionImportID: recognitionImportID,
            reimbursementStatus: kind == .expense ? reimbursementStatus : .none
        )
    }

    private static func string(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    var originalAmountText: String {
        get { originalAmount.map(Self.string) ?? "" }
        set { originalAmount = DecimalParser.parse(newValue) }
    }

    var discountAmountText: String {
        get { discountAmount.map(Self.string) ?? "" }
        set { discountAmount = DecimalParser.parse(newValue) }
    }

    mutating func setSplitPaymentEnabled(_ enabled: Bool, wallets: [CurrencyWallet]) {
        usesSplitPayment = enabled
        guard enabled else {
            paymentParts = []
            return
        }
        let sourceID = sourceWalletID
        let sourceCode = wallets.first { $0.id == sourceID }?.currencyCode
        let secondID = wallets.first {
            $0.id != sourceID && $0.currencyCode == sourceCode
        }?.id
        paymentParts = [
            PaymentPartFormState(walletID: sourceID),
            PaymentPartFormState(walletID: secondID)
        ]
    }

    mutating func synchronizePrimaryPaymentWallet() {
        guard usesSplitPayment, !paymentParts.isEmpty else { return }
        paymentParts[0].walletID = sourceWalletID
    }
}

struct PaymentPartFormState: Identifiable, Equatable {
    let id: UUID
    var walletID: UUID?
    var amountText: String

    init(id: UUID = UUID(), walletID: UUID?, amountText: String = "") {
        self.id = id
        self.walletID = walletID
        self.amountText = amountText
    }
}
