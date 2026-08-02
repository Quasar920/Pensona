import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var note: String?
    var isHidden: Bool
    var isArchived: Bool = false
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var defaultForeignCurrencySettlementModeRawValue: String?
    var defaultSettlementCurrencyCode: String?
    var book: LedgerBook?
    @Relationship(deleteRule: .cascade, inverse: \CurrencyWallet.account)
    var wallets: [CurrencyWallet]

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        note: String? = nil,
        book: LedgerBook? = nil,
        isHidden: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        defaultForeignCurrencySettlementMode: ForeignCurrencySettlementMode? = nil,
        defaultSettlementCurrencyCode: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        typeRawValue = type.rawValue
        self.note = note
        self.book = book
        self.isHidden = isHidden
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        defaultForeignCurrencySettlementModeRawValue = defaultForeignCurrencySettlementMode?.rawValue
        self.defaultSettlementCurrencyCode = defaultSettlementCurrencyCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        wallets = []
    }

    var type: AccountType { AccountType(rawValue: typeRawValue) ?? .other }
    var defaultForeignCurrencySettlementMode: ForeignCurrencySettlementMode {
        get {
            defaultForeignCurrencySettlementModeRawValue
                .flatMap(ForeignCurrencySettlementMode.init(rawValue:)) ?? .instant
        }
        set {
            defaultForeignCurrencySettlementModeRawValue = newValue.rawValue
        }
    }

    var enabledWallets: [CurrencyWallet] {
        wallets.filter(\.isEnabled).sorted { $0.currencyCode < $1.currencyCode }
    }

    var allWallets: [CurrencyWallet] {
        wallets.sorted { $0.currencyCode < $1.currencyCode }
    }
}

extension Account: Identifiable {}
