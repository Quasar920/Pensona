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
    var discountWalletID: UUID?
    var date: Date
    var note: String
    var merchantOrCounterparty: String
    var adjustmentDirection: AdjustmentDirection
    var adjustmentInputMode: AdjustmentInputMode
    var adjustmentReason: String
    var reimbursementStatus: ReimbursementStatus
    var excludesFromMonthlyIncome: Bool
    var excludesFromMonthlyExpense: Bool
    var includesFee: Bool
    var feeText: String
    var feeRatePercentage: Decimal?
    var feeTemplateName: String?
    var settledAmountText: String
    var referenceExchangeRateText: String
    var foreignSettlementMode: ForeignCurrencySettlementMode?
    var foreignOriginalCurrencyCode: String?
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
            || !settledAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !referenceExchangeRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !merchantOrCounterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (includesFee && !feeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || discountAmount != nil
            || foreignSettlementMode != nil
            || paymentParts.contains { !$0.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || aaSplitDraft != nil
            || reimbursementStatus == .pending
            || excludesFromMonthlyIncome
            || excludesFromMonthlyExpense
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
        discountWalletID = nil
        self.date = date
        note = ""
        merchantOrCounterparty = ""
        adjustmentDirection = .increase
        adjustmentInputMode = .delta
        adjustmentReason = "手动校准"
        reimbursementStatus = .none
        excludesFromMonthlyIncome = false
        excludesFromMonthlyExpense = false
        includesFee = false
        feeText = ""
        feeRatePercentage = nil
        feeTemplateName = nil
        settledAmountText = ""
        referenceExchangeRateText = ""
        foreignSettlementMode = nil
        foreignOriginalCurrencyCode = nil
        usesSplitPayment = false
        paymentParts = []
        aaSplitDraft = nil
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
    }

    init(draft: TransactionDraft) {
        kind = draft.type
        amountText = Self.string(draft.foreignOriginalAmount ?? draft.amount)
        destinationAmountText = draft.destinationAmount.map(Self.string) ?? ""
        if draft.type == .exchange, draft.amount > 0, let destinationAmount = draft.destinationAmount {
            exchangeRateText = Self.string(destinationAmount / draft.amount)
        } else if draft.transferPurpose == .creditCardRepayment,
                  let destinationAmount = draft.destinationAmount,
                  destinationAmount > 0 {
            exchangeRateText = Self.string(draft.amount / destinationAmount)
        } else {
            exchangeRateText = ""
        }
        sourceWalletID = draft.sourceWallet?.id
        destinationWalletID = draft.destinationWallet?.id
        categoryID = draft.category?.id
        feeWalletID = draft.feeWallet?.id
        discountWalletID = draft.discountWallet?.id
        date = draft.date
        note = draft.note ?? ""
        merchantOrCounterparty = draft.merchantOrCounterparty ?? ""
        adjustmentDirection = draft.adjustmentDirection ?? .increase
        adjustmentInputMode = .delta
        adjustmentReason = draft.adjustmentReason ?? "手动校准"
        reimbursementStatus = draft.reimbursementStatus
        excludesFromMonthlyIncome = draft.excludesFromMonthlyIncome
        excludesFromMonthlyExpense = draft.excludesFromMonthlyExpense
        includesFee = draft.feeAmount != nil
        feeText = draft.feeAmount.map(Self.string) ?? ""
        if draft.type == .income,
           let original = draft.originalAmount,
           original > 0,
           let fee = draft.feeAmount {
            feeRatePercentage = fee * 100 / original
        } else {
            feeRatePercentage = nil
        }
        feeTemplateName = nil
        settledAmountText = draft.settledAmount.map(Self.string) ?? ""
        referenceExchangeRateText = draft.referenceExchangeRate.map(Self.string) ?? ""
        foreignSettlementMode = draft.foreignSettlementMode
        foreignOriginalCurrencyCode = draft.foreignOriginalCurrencyCode
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
        if includesFee, let originalAmount {
            amountText = Self.string(originalAmount)
        }
        categoryID = nil
        destinationWalletID = nil
        feeWalletID = nil
        discountWalletID = nil
        destinationAmountText = ""
        exchangeRateText = ""
        includesFee = false
        feeText = ""
        feeRatePercentage = nil
        feeTemplateName = nil
        originalAmount = nil
        settledAmountText = ""
        referenceExchangeRateText = ""
        foreignSettlementMode = nil
        foreignOriginalCurrencyCode = nil
        adjustmentDirection = .increase
        adjustmentInputMode = .delta
        adjustmentReason = "手动校准"
        reimbursementStatus = .none
        excludesFromMonthlyIncome = false
        excludesFromMonthlyExpense = false
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
        feeRatePercentage = nil
        feeTemplateName = nil
        feeWalletID = sourceWalletID
        discountWalletID = nil
        note = ""
        merchantOrCounterparty = ""
        for index in paymentParts.indices { paymentParts[index].amountText = "" }
        aaSplitDraft = nil
        reimbursementStatus = .none
        excludesFromMonthlyIncome = false
        excludesFromMonthlyExpense = false
        originalAmount = nil
        discountAmount = nil
        recognitionImportID = nil
        settledAmountText = ""
        referenceExchangeRateText = ""
        foreignSettlementMode = nil
        foreignOriginalCurrencyCode = nil
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

        var amount: Decimal
        var resolvedSourceWallet = sourceWallet
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

        let accountSettlementCode = sourceWallet.account?.defaultSettlementCurrencyCode
            ?? sourceWallet.currencyCode
        let foreignCode = foreignOriginalCurrencyCode
        let isForeignCreditExpense = kind == .expense
            && sourceWallet.account?.type == .creditCard
            && foreignCode != nil
            && foreignCode != accountSettlementCode
        let resolvedForeignMode = isForeignCreditExpense
            ? (foreignSettlementMode ?? sourceWallet.account?.defaultForeignCurrencySettlementMode ?? .instant)
            : nil
        if isForeignCreditExpense, let foreignCode {
            switch resolvedForeignMode {
            case .instant:
                guard let settled = DecimalParser.parse(settledAmountText), settled > 0 else {
                    throw ForeignCurrencySettlementError.missingSettlementAmount
                }
                guard let settlementWallet = wallets.first(where: {
                    $0.account?.id == sourceWallet.account?.id
                        && $0.currencyCode == accountSettlementCode
                }) else {
                    throw ValidationError("请先为信用卡添加默认结算币种")
                }
                amount = settled
                resolvedSourceWallet = settlementWallet
            case .repayment:
                guard let foreignWallet = wallets.first(where: {
                    $0.account?.id == sourceWallet.account?.id
                        && $0.currencyCode == foreignCode
                }) else {
                    throw ValidationError("请先为信用卡添加所选外币")
                }
                amount = enteredAmount
                resolvedSourceWallet = foreignWallet
            case nil:
                break
            }
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
            if destinationWallet?.account?.type == .creditCard,
               destinationWallet?.currencyCode != resolvedSourceWallet.currencyCode {
                guard let parsed = DecimalParser.parse(destinationAmountText), parsed > 0 else {
                    throw ValidationError("请输入大于 0 的外币偿还金额")
                }
                destinationAmount = parsed
            } else {
                destinationAmount = amount
            }
        case .exchange:
            guard let parsed = DecimalParser.parse(destinationAmountText), parsed > 0 else {
                throw ValidationError("请输入大于 0 的换入金额")
            }
            destinationAmount = parsed
        default:
            destinationAmount = nil
        }

        let resolvedDiscountAmount = discountAmount
        let resolvedDiscountWallet: CurrencyWallet?
        if kind == .transfer, let resolvedDiscountAmount, resolvedDiscountAmount > 0 {
            guard let selected = wallets.first(where: { $0.id == discountWalletID }) else {
                throw ValidationError("请选择优惠进入的钱包")
            }
            resolvedDiscountWallet = selected
        } else {
            resolvedDiscountWallet = nil
        }

        let feeAmount: Decimal?
        let feeWallet: CurrencyWallet?
        if includesFee {
            guard let parsed = DecimalParser.parse(feeText), parsed > 0 else {
                throw ValidationError("请输入大于 0 的手续费")
            }
            feeAmount = parsed
            switch kind {
            case .income:
                feeWallet = nil
            case .expense:
                feeWallet = resolvedSourceWallet
            case .transfer, .exchange:
                guard let selectedFeeWallet = wallets.first(where: { $0.id == feeWalletID }) else {
                    throw ValidationError("请选择手续费钱包")
                }
                feeWallet = selectedFeeWallet
            case .adjustment:
                feeWallet = nil
            }
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
            sourceWallet: resolvedSourceWallet,
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
            discountAmount: resolvedDiscountAmount,
            discountWallet: resolvedDiscountWallet,
            recognitionImportID: recognitionImportID,
            transferPurpose: kind == .transfer && destinationWallet?.account?.type == .creditCard
                ? .creditCardRepayment
                : .standard,
            foreignSettlementMode: resolvedForeignMode,
            foreignOriginalAmount: isForeignCreditExpense ? enteredAmount : nil,
            foreignOriginalCurrencyCode: isForeignCreditExpense ? foreignCode : nil,
            settlementCurrencyCode: isForeignCreditExpense ? accountSettlementCode : nil,
            settledAmount: resolvedForeignMode == .instant ? amount : nil,
            referenceExchangeRate: DecimalParser.parse(referenceExchangeRateText),
            reimbursementStatus: kind == .expense ? reimbursementStatus : .none,
            excludesFromMonthlyIncome: kind == .income && excludesFromMonthlyIncome,
            excludesFromMonthlyExpense: kind == .expense && excludesFromMonthlyExpense
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

    var feeCalculationBaseAmount: Decimal? {
        if kind == .income, let originalAmount, includesFee {
            return originalAmount
        }
        return DecimalParser.parse(amountText)
    }

    mutating func applyFee(
        inputText: String,
        mode: FeeInputMode,
        currencyCode: String,
        templateName: String? = nil
    ) -> Bool {
        guard let baseAmount = feeCalculationBaseAmount,
              baseAmount > 0,
              let input = DecimalParser.parse(inputText),
              input > 0 else {
            return false
        }
        let fee = FeeCalculator.fee(
            baseAmount: baseAmount,
            input: input,
            mode: mode,
            currencyCode: currencyCode
        )
        guard fee > 0, kind != .income || fee < baseAmount else { return false }

        includesFee = true
        feeText = Self.string(fee)
        feeRatePercentage = mode == .percentage ? input : nil
        feeTemplateName = templateName
        if kind == .income {
            originalAmount = baseAmount
            amountText = Self.string(
                FeeCalculator.rounded(baseAmount - fee, currencyCode: currencyCode)
            )
            feeWalletID = nil
        } else if feeWalletID == nil {
            feeWalletID = sourceWalletID
        }
        return true
    }

    mutating func clearFee() {
        if kind == .income, let originalAmount, includesFee {
            amountText = Self.string(originalAmount)
            self.originalAmount = nil
        }
        includesFee = false
        feeText = ""
        feeRatePercentage = nil
        feeTemplateName = nil
        feeWalletID = nil
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
