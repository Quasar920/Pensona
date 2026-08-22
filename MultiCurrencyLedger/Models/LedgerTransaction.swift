import Foundation
import SwiftData

enum ReimbursementStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case none
    case pending
}

@Model
final class LedgerTransaction {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var amount: Decimal?
    var currencyCode: String?
    var date: Date
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    /// Optional at the schema boundary so stores from before V3 can open. All
    /// new transactions are required to receive a value through LedgerService.
    var bookID: UUID?
    var reimbursementStatusRawValue: String = ReimbursementStatus.none.rawValue

    var sourceAmount: Decimal?
    var sourceCurrencyCode: String?
    var destinationAmount: Decimal?
    var destinationCurrencyCode: String?
    var feeAmount: Decimal?
    var feeCurrencyCode: String?
    var exchangeRate: Decimal?
    var adjustmentDirectionRawValue: String?
    var adjustmentReason: String?
    var merchantOrCounterparty: String?
    var originalAmount: Decimal?
    var discountAmount: Decimal?
    var recognitionImportID: UUID?
    var transferPurposeRawValue: String = TransferPurpose.standard.rawValue
    var foreignSettlementModeRawValue: String?
    var foreignOriginalAmount: Decimal?
    var foreignOriginalCurrencyCode: String?
    var settlementCurrencyCode: String?
    var settledAmount: Decimal?
    var settlementExchangeRate: Decimal?
    var referenceExchangeRate: Decimal?
    var discountCurrencyCode: String?
    var installmentPlanID: UUID?
    var installmentIndex: Int?

    @Relationship(deleteRule: .nullify) var sourceAccount: Account?
    @Relationship(deleteRule: .nullify) var sourceWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var destinationAccount: Account?
    @Relationship(deleteRule: .nullify) var destinationWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var feeWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var discountWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var category: LedgerCategory?
    @Relationship(inverse: \TransactionTag.transactions) var tags: [TransactionTag]
    @Relationship(deleteRule: .cascade, inverse: \TransactionPaymentPart.transaction)
    var paymentParts: [TransactionPaymentPart]

    init(
        id: UUID = UUID(),
        type: TransactionKind,
        bookID: UUID? = nil,
        reimbursementStatus: ReimbursementStatus = .none,
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        date: Date = .now,
        note: String? = nil,
        sourceAccount: Account? = nil,
        sourceWallet: CurrencyWallet? = nil,
        destinationAccount: Account? = nil,
        destinationWallet: CurrencyWallet? = nil,
        sourceAmount: Decimal? = nil,
        sourceCurrencyCode: String? = nil,
        destinationAmount: Decimal? = nil,
        destinationCurrencyCode: String? = nil,
        feeAmount: Decimal? = nil,
        feeCurrencyCode: String? = nil,
        feeWallet: CurrencyWallet? = nil,
        exchangeRate: Decimal? = nil,
        adjustmentDirection: AdjustmentDirection? = nil,
        adjustmentReason: String? = nil,
        category: LedgerCategory? = nil,
        tags: [TransactionTag] = [],
        paymentParts: [TransactionPaymentPart] = [],
        merchantOrCounterparty: String? = nil,
        originalAmount: Decimal? = nil,
        discountAmount: Decimal? = nil,
        recognitionImportID: UUID? = nil,
        transferPurpose: TransferPurpose = .standard,
        foreignSettlementMode: ForeignCurrencySettlementMode? = nil,
        foreignOriginalAmount: Decimal? = nil,
        foreignOriginalCurrencyCode: String? = nil,
        settlementCurrencyCode: String? = nil,
        settledAmount: Decimal? = nil,
        settlementExchangeRate: Decimal? = nil,
        referenceExchangeRate: Decimal? = nil,
        discountWallet: CurrencyWallet? = nil,
        discountCurrencyCode: String? = nil,
        installmentPlanID: UUID? = nil,
        installmentIndex: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.bookID = bookID
        reimbursementStatusRawValue = reimbursementStatus.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.note = note
        self.sourceAccount = sourceAccount
        self.sourceWallet = sourceWallet
        self.destinationAccount = destinationAccount
        self.destinationWallet = destinationWallet
        self.sourceAmount = sourceAmount
        self.sourceCurrencyCode = sourceCurrencyCode
        self.destinationAmount = destinationAmount
        self.destinationCurrencyCode = destinationCurrencyCode
        self.feeAmount = feeAmount
        self.feeCurrencyCode = feeCurrencyCode
        self.feeWallet = feeWallet
        self.exchangeRate = exchangeRate
        adjustmentDirectionRawValue = adjustmentDirection?.rawValue
        self.adjustmentReason = adjustmentReason
        self.category = category
        self.tags = tags
        self.paymentParts = paymentParts
        self.merchantOrCounterparty = merchantOrCounterparty
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.recognitionImportID = recognitionImportID
        transferPurposeRawValue = transferPurpose.rawValue
        foreignSettlementModeRawValue = foreignSettlementMode?.rawValue
        self.foreignOriginalAmount = foreignOriginalAmount
        self.foreignOriginalCurrencyCode = foreignOriginalCurrencyCode
        self.settlementCurrencyCode = settlementCurrencyCode
        self.settledAmount = settledAmount
        self.settlementExchangeRate = settlementExchangeRate
        self.referenceExchangeRate = referenceExchangeRate
        self.discountWallet = discountWallet
        self.discountCurrencyCode = discountCurrencyCode
        self.installmentPlanID = installmentPlanID
        self.installmentIndex = installmentIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: TransactionKind { TransactionKind(rawValue: typeRawValue) ?? .expense }
    var reimbursementStatus: ReimbursementStatus {
        get { ReimbursementStatus(rawValue: reimbursementStatusRawValue) ?? .none }
        set { reimbursementStatusRawValue = newValue.rawValue }
    }
    var adjustmentDirection: AdjustmentDirection? {
        adjustmentDirectionRawValue.flatMap(AdjustmentDirection.init(rawValue:))
    }
    var transferPurpose: TransferPurpose {
        get { TransferPurpose(rawValue: transferPurposeRawValue) ?? .standard }
        set { transferPurposeRawValue = newValue.rawValue }
    }

    /// Older discounted expenses stored the sticker price in `sourceAmount`
    /// and left `originalAmount` empty. Newer entries store the paid amount
    /// and keep the sticker price in `originalAmount`. Refund calculations
    /// must use the amount actually paid in both representations.
    var netExpenseAmount: Decimal {
        let principal = sourceAmount ?? amount ?? 0
        guard type == .expense,
              originalAmount == nil,
              let discountAmount,
              discountAmount > 0,
              (discountCurrencyCode == nil || discountCurrencyCode == sourceCurrencyCode || discountCurrencyCode == currencyCode)
        else { return principal }
        return max(0, principal - discountAmount)
    }
    var foreignSettlementMode: ForeignCurrencySettlementMode? {
        get { foreignSettlementModeRawValue.flatMap(ForeignCurrencySettlementMode.init(rawValue:)) }
        set { foreignSettlementModeRawValue = newValue?.rawValue }
    }
}
