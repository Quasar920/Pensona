import Foundation

enum AssetDashboardGroup: String, CaseIterable, Identifiable {
    case bankCards, credit, cash, investment, storedValue, lending, legacyOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bankCards: AppLocalization.string( "银行卡")
        case .credit: AppLocalization.string( "信用账户")
        case .cash: AppLocalization.string( "现金")
        case .investment: AppLocalization.string( "投资账户")
        case .storedValue: AppLocalization.string( "储值卡")
        case .lending: AppLocalization.string( "借贷账户")
        case .legacyOther: AppLocalization.string( "其他（待归类）")
        }
    }

    var symbolName: String {
        switch self {
        case .bankCards: "building.columns.fill"
        case .credit: "creditcard.and.123"
        case .cash: "banknote.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .storedValue: "wallet.pass.fill"
        case .lending: "arrow.left.arrow.right.circle.fill"
        case .legacyOther: "questionmark.square.fill"
        }
    }

    static func group(for type: AccountType) -> AssetDashboardGroup {
        switch type {
        case .bankCard, .savings: .bankCards
        case .creditCard: .credit
        case .cash: .cash
        case .investment: .investment
        case .eWallet: .storedValue
        case .receivable, .payable: .lending
        case .other: .legacyOther
        }
    }
}

enum AssetModuleKind: String, CaseIterable, Identifiable {
    case aa, reimbursement, borrowed, lent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aa: AppLocalization.string( "AA")
        case .reimbursement: AppLocalization.string( "报销")
        case .borrowed: AppLocalization.string( "借入")
        case .lent: AppLocalization.string( "借出")
        }
    }
    var symbolName: String {
        switch self {
        case .aa: "person.2.fill"
        case .reimbursement: "arrow.uturn.backward.circle.fill"
        case .borrowed: "arrow.down.left.circle.fill"
        case .lent: "arrow.up.right.circle.fill"
        }
    }
}

struct AssetModuleSnapshot: Identifiable, Equatable {
    let kind: AssetModuleKind
    let amount: Decimal
    let count: Int
    let missingCodes: Set<String>
    var id: AssetModuleKind { kind }
}

struct AssetAccountRowSnapshot: Identifiable {
    let account: Account
    let amount: Decimal
    let missingCodes: Set<String>
    var id: UUID { account.id }
}

struct AssetAccountGroupSnapshot: Identifiable {
    let group: AssetDashboardGroup
    let subtotal: Decimal
    let rows: [AssetAccountRowSnapshot]
    var id: AssetDashboardGroup { group }
}

struct AssetDashboardSnapshot {
    let totalAssets: Decimal
    let modules: [AssetModuleSnapshot]
    let groups: [AssetAccountGroupSnapshot]
    let missingCodes: Set<String>
}
