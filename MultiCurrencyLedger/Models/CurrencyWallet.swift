import Foundation
import SwiftData

@Model
final class CurrencyWallet {
    @Attribute(.unique) var id: UUID
    var currencyCode: String
    var balance: Decimal
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var account: Account?

    init(
        id: UUID = UUID(),
        currency: SupportedCurrency,
        balance: Decimal = .zero,
        isEnabled: Bool = true,
        account: Account? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        currencyCode = currency.rawValue
        self.balance = balance
        self.isEnabled = isEnabled
        self.account = account
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var currency: SupportedCurrency? { SupportedCurrency(rawValue: currencyCode) }
}
