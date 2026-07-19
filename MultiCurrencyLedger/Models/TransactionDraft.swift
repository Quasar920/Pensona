import Foundation

/// The single editable representation used by every transaction entry point.
/// It contains user intent only and never mutates wallet balances by itself.
struct TransactionDraft {
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
    var recognitionImportID: UUID?

    init(
        type: TransactionKind,
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
        recognitionImportID: UUID? = nil
    ) {
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
        self.recognitionImportID = recognitionImportID
    }

    init(transaction: LedgerTransaction) {
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
        recognitionImportID = transaction.recognitionImportID
    }

    func makeTransaction(
        id: UUID = UUID(),
        createdAt: Date = .now
    ) -> LedgerTransaction {
        let transaction = LedgerTransaction(
            id: id,
            type: type,
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
        case .transfer: amount
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
        transaction.recognitionImportID = recognitionImportID
        transaction.updatedAt = .now
    }
}
