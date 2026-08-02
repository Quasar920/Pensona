import Foundation

/// The single editable representation used by every transaction entry point.
/// It contains user intent only and never mutates wallet balances by itself.
struct TransactionDraft {
    /// Carries caller scope between non-persistent entry screens. LedgerService
    /// still requires the same scope explicitly and never infers it from here.
    var bookID: UUID?
    var type: TransactionKind
    var amount: Decimal
    var sourceWallet: CurrencyWallet?
    var destinationWallet: CurrencyWallet?
    var destinationAmount: Decimal?
    var feeAmount: Decimal?
    var feeWallet: CurrencyWallet?
    var date: Date
    var note: String?
    var merchantOrCounterparty: String?
    var category: LedgerCategory?
    var paymentParts: [TransactionPaymentPartDraft]
    var adjustmentDirection: AdjustmentDirection?
    var adjustmentReason: String?
    var originalAmount: Decimal?
    var discountAmount: Decimal?
    var discountWallet: CurrencyWallet?
    var recognitionImportID: UUID?
    var transferPurpose: TransferPurpose
    var foreignSettlementMode: ForeignCurrencySettlementMode?
    var foreignOriginalAmount: Decimal?
    var foreignOriginalCurrencyCode: String?
    var settlementCurrencyCode: String?
    var settledAmount: Decimal?
    var settlementExchangeRate: Decimal?
    var referenceExchangeRate: Decimal?
    var installmentPlanID: UUID?
    var installmentIndex: Int?
    var reimbursementStatus: ReimbursementStatus
    var excludesFromMonthlyIncome: Bool
    var excludesFromMonthlyExpense: Bool

    init(
        type: TransactionKind,
        bookID: UUID? = nil,
        amount: Decimal,
        sourceWallet: CurrencyWallet?,
        destinationWallet: CurrencyWallet? = nil,
        destinationAmount: Decimal? = nil,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        date: Date = .now,
        note: String? = nil,
        merchantOrCounterparty: String? = nil,
        category: LedgerCategory? = nil,
        paymentParts: [TransactionPaymentPartDraft] = [],
        adjustmentDirection: AdjustmentDirection? = nil,
        adjustmentReason: String? = nil,
        originalAmount: Decimal? = nil,
        discountAmount: Decimal? = nil,
        discountWallet: CurrencyWallet? = nil,
        recognitionImportID: UUID? = nil,
        transferPurpose: TransferPurpose = .standard,
        foreignSettlementMode: ForeignCurrencySettlementMode? = nil,
        foreignOriginalAmount: Decimal? = nil,
        foreignOriginalCurrencyCode: String? = nil,
        settlementCurrencyCode: String? = nil,
        settledAmount: Decimal? = nil,
        settlementExchangeRate: Decimal? = nil,
        referenceExchangeRate: Decimal? = nil,
        installmentPlanID: UUID? = nil,
        installmentIndex: Int? = nil,
        reimbursementStatus: ReimbursementStatus = .none,
        excludesFromMonthlyIncome: Bool = false,
        excludesFromMonthlyExpense: Bool = false
    ) {
        self.bookID = bookID
        self.type = type
        self.amount = amount
        self.sourceWallet = sourceWallet
        self.destinationWallet = destinationWallet
        self.destinationAmount = destinationAmount
        self.feeAmount = feeAmount
        self.feeWallet = feeWallet
        self.date = date
        self.note = note
        self.merchantOrCounterparty = merchantOrCounterparty
        self.category = category
        self.paymentParts = paymentParts
        self.adjustmentDirection = adjustmentDirection
        self.adjustmentReason = adjustmentReason
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.discountWallet = discountWallet
        self.recognitionImportID = recognitionImportID
        self.transferPurpose = transferPurpose
        self.foreignSettlementMode = foreignSettlementMode
        self.foreignOriginalAmount = foreignOriginalAmount
        self.foreignOriginalCurrencyCode = foreignOriginalCurrencyCode
        self.settlementCurrencyCode = settlementCurrencyCode
        self.settledAmount = settledAmount
        self.settlementExchangeRate = settlementExchangeRate
        self.referenceExchangeRate = referenceExchangeRate
        self.installmentPlanID = installmentPlanID
        self.installmentIndex = installmentIndex
        self.reimbursementStatus = reimbursementStatus
        self.excludesFromMonthlyIncome = excludesFromMonthlyIncome
        self.excludesFromMonthlyExpense = excludesFromMonthlyExpense
    }

    init(transaction: LedgerTransaction) {
        bookID = transaction.bookID
        type = transaction.type
        amount = transaction.sourceAmount ?? transaction.amount ?? 0
        sourceWallet = transaction.sourceWallet
        destinationWallet = transaction.destinationWallet
        destinationAmount = transaction.destinationAmount
        feeAmount = transaction.feeAmount
        feeWallet = transaction.feeWallet
        date = transaction.date
        note = transaction.note
        merchantOrCounterparty = transaction.merchantOrCounterparty
        category = transaction.category
        paymentParts = transaction.paymentParts
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { part in
                part.wallet.map { TransactionPaymentPartDraft(wallet: $0, amount: part.amount) }
            }
        adjustmentDirection = transaction.adjustmentDirection
        adjustmentReason = transaction.adjustmentReason
        originalAmount = transaction.originalAmount
        discountAmount = transaction.discountAmount
        discountWallet = transaction.discountWallet
        recognitionImportID = transaction.recognitionImportID
        transferPurpose = transaction.transferPurpose
        foreignSettlementMode = transaction.foreignSettlementMode
        foreignOriginalAmount = transaction.foreignOriginalAmount
        foreignOriginalCurrencyCode = transaction.foreignOriginalCurrencyCode
        settlementCurrencyCode = transaction.settlementCurrencyCode
        settledAmount = transaction.settledAmount
        settlementExchangeRate = transaction.settlementExchangeRate
        referenceExchangeRate = transaction.referenceExchangeRate
        installmentPlanID = transaction.installmentPlanID
        installmentIndex = transaction.installmentIndex
        reimbursementStatus = transaction.reimbursementStatus
        let exclusion = MonthlySummaryExclusionStore.exclusion(for: transaction.id)
        excludesFromMonthlyIncome = exclusion.income
        excludesFromMonthlyExpense = exclusion.expense
    }

    func makeTransaction(
        bookID: UUID,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) -> LedgerTransaction {
        let transaction = LedgerTransaction(
            id: id,
            type: type,
            bookID: bookID,
            createdAt: createdAt
        )
        apply(to: transaction)
        return transaction
    }

    func apply(to transaction: LedgerTransaction) {
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMerchant = merchantOrCounterparty?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMovement = type == .transfer || type == .exchange
        let isCategorized = type == .expense || type == .income

        transaction.typeRawValue = type.rawValue
        transaction.amount = isMovement ? nil : amount
        transaction.currencyCode = isMovement ? nil : sourceWallet?.currencyCode
        transaction.date = date
        transaction.note = cleanNote?.isEmpty == true ? nil : cleanNote
        transaction.sourceAccount = sourceWallet?.account
        transaction.sourceWallet = sourceWallet
        transaction.destinationAccount = isMovement ? destinationWallet?.account : nil
        transaction.destinationWallet = isMovement ? destinationWallet : nil
        transaction.sourceAmount = amount
        transaction.sourceCurrencyCode = sourceWallet?.currencyCode
        transaction.destinationAmount = switch type {
        case .transfer: destinationAmount ?? amount
        case .exchange: destinationAmount
        default: nil
        }
        transaction.destinationCurrencyCode = isMovement ? destinationWallet?.currencyCode : nil
        transaction.feeAmount = isMovement ? feeAmount : nil
        transaction.feeCurrencyCode = isMovement ? feeWallet?.currencyCode : nil
        transaction.feeWallet = isMovement && feeAmount != nil ? feeWallet : nil
        if type == .exchange, amount > 0, let destinationAmount {
            transaction.exchangeRate = destinationAmount / amount
        } else {
            transaction.exchangeRate = nil
        }
        transaction.adjustmentDirectionRawValue = type == .adjustment
            ? adjustmentDirection?.rawValue
            : nil
        transaction.adjustmentReason = type == .adjustment
            ? adjustmentReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        transaction.category = isCategorized ? category : nil
        transaction.tags.removeAll()
        transaction.paymentParts = paymentParts.enumerated().map { index, part in
            TransactionPaymentPart(
                amount: part.amount,
                sortOrder: index,
                transaction: transaction,
                wallet: part.wallet
            )
        }
        transaction.merchantOrCounterparty = cleanMerchant?.isEmpty == true ? nil : cleanMerchant
        transaction.originalAmount = originalAmount
        transaction.discountAmount = discountAmount
        transaction.discountWallet = type == .transfer ? discountWallet : nil
        transaction.discountCurrencyCode = type == .transfer && discountAmount != nil
            ? discountWallet?.currencyCode
            : nil
        transaction.recognitionImportID = recognitionImportID
        transaction.transferPurpose = type == .transfer ? transferPurpose : .standard
        transaction.foreignSettlementMode = foreignSettlementMode
        transaction.foreignOriginalAmount = foreignOriginalAmount
        transaction.foreignOriginalCurrencyCode = foreignOriginalCurrencyCode
        transaction.settlementCurrencyCode = settlementCurrencyCode
        transaction.settledAmount = settledAmount
        if type == .expense,
           foreignSettlementMode == .instant,
           let settledAmount,
           let foreignOriginalAmount,
           foreignOriginalAmount > 0 {
            transaction.settlementExchangeRate = settledAmount / foreignOriginalAmount
        } else if type == .transfer,
                  transferPurpose == .creditCardRepayment,
                  sourceWallet?.currencyCode != destinationWallet?.currencyCode,
                  let destinationAmount = transaction.destinationAmount,
                  destinationAmount > 0 {
            transaction.settlementExchangeRate = amount / destinationAmount
        } else {
            transaction.settlementExchangeRate = settlementExchangeRate
        }
        transaction.referenceExchangeRate = referenceExchangeRate
        transaction.installmentPlanID = installmentPlanID
        transaction.installmentIndex = installmentIndex
        transaction.reimbursementStatus = reimbursementStatus
        transaction.updatedAt = .now
    }
}
