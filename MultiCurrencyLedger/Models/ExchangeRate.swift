import Foundation
import SwiftData

@Model
final class ExchangeRate {
    @Attribute(.unique) var id: UUID
    var currencyCode: String
    var baseCurrencyCode: String
    var rate: Decimal
    var sourceRawValue: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        currencyCode: String,
        baseCurrencyCode: String,
        rate: Decimal,
        source: ExchangeRateSource = .manual,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.currencyCode = currencyCode
        self.baseCurrencyCode = baseCurrencyCode
        self.rate = rate
        sourceRawValue = source.rawValue
        self.updatedAt = updatedAt
    }

    var source: ExchangeRateSource {
        ExchangeRateSource(rawValue: sourceRawValue) ?? .manual
    }
}
