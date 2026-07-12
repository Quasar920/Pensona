import Foundation
import SwiftData

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

    @Relationship(deleteRule: .nullify) var sourceAccount: Account?
    @Relationship(deleteRule: .nullify) var sourceWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var destinationAccount: Account?
    @Relationship(deleteRule: .nullify) var destinationWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var feeWallet: CurrencyWallet?
    @Relationship(deleteRule: .nullify) var category: LedgerCategory?

    init(
        id: UUID = UUID(),
        type: TransactionKind,
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
        merchantOrCounterparty: String? = nil,
        originalAmount: Decimal? = nil,
        discountAmount: Decimal? = nil,
        recognitionImportID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        typeRawValue = type.rawValue
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
        self.merchantOrCounterparty = merchantOrCounterparty
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.recognitionImportID = recognitionImportID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: TransactionKind { TransactionKind(rawValue: typeRawValue) ?? .expense }
    var adjustmentDirection: AdjustmentDirection? {
        adjustmentDirectionRawValue.flatMap(AdjustmentDirection.init(rawValue:))
    }
}
