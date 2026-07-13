import Foundation

enum SupportedCurrency: String, CaseIterable, Codable, Identifiable, Sendable {
    case AED, ARS, AUD, BDT, BGN, BHD, BRL, CAD, CHF, CLP
    case CNY, COP, CZK, DKK, EGP, EUR, GBP, GEL, GHS, HKD
    case HUF, IDR, ILS, INR, ISK, JOD, JPY, KES, KRW, KWD
    case KZT, LKR, MAD, MXN, MYR, NGN, NOK, NZD, OMR, PEN
    case PHP, PKR, PLN, QAR, RON, RSD, RUB, SAR, SEK, SGD
    case THB, TND, TRY, TWD, UAH, USD, UYU, VND, ZAR

    var id: String { rawValue }
    var code: String { rawValue }
    var fractionDigits: Int {
        switch self {
        case .CLP, .ISK, .JPY, .KRW, .VND:
            0
        case .BHD, .JOD, .KWD, .OMR, .TND:
            3
        default:
            2
        }
    }

    static func fractionDigits(for code: String) -> Int {
        SupportedCurrency(rawValue: code.uppercased())?.fractionDigits ?? 2
    }

    var localizedName: String {
        Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
    }
}

enum AccountType: String, CaseIterable, Codable, Identifiable {
    case bankCard, cash, eWallet, creditCard, savings, investment, other
    case receivable, payable

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bankCard: "银行卡"
        case .cash: "现金"
        case .eWallet: "电子钱包"
        case .creditCard: "信用卡"
        case .savings: "储蓄账户"
        case .investment: "投资账户"
        case .other: "其他"
        case .receivable: "应收账款"
        case .payable: "应付账款"
        }
    }

    var symbolName: String {
        switch self {
        case .bankCard: "creditcard.fill"
        case .cash: "banknote.fill"
        case .eWallet: "wallet.pass.fill"
        case .creditCard: "creditcard.and.123"
        case .savings: "building.columns.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .other: "square.grid.2x2.fill"
        case .receivable: "arrow.down.left.circle.fill"
        case .payable: "arrow.up.right.circle.fill"
        }
    }

    var assetGroup: AssetGroup {
        switch self {
        case .bankCard, .cash, .savings, .other:
            .cash
        case .creditCard:
            .credit
        case .eWallet:
            .recharge
        case .investment:
            .investment
        case .receivable:
            .receivable
        case .payable:
            .payable
        }
    }

    var canonicalAccountType: AccountType { assetGroup.canonicalAccountType }
    var isLiability: Bool { assetGroup.isLiability }
}

enum AssetGroup: String, CaseIterable, Codable, Identifiable {
    case cash, credit, recharge, investment, receivable, payable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "现金账户"
        case .credit: "信用账户"
        case .recharge: "充值账户"
        case .investment: "理财账户"
        case .receivable: "应收账款"
        case .payable: "应付账款"
        }
    }

    var symbolName: String {
        switch self {
        case .cash: "banknote.fill"
        case .credit: "creditcard.and.123"
        case .recharge: "wallet.pass.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .receivable: "arrow.down.left.circle.fill"
        case .payable: "arrow.up.right.circle.fill"
        }
    }

    var canonicalAccountType: AccountType {
        switch self {
        case .cash: .cash
        case .credit: .creditCard
        case .recharge: .eWallet
        case .investment: .investment
        case .receivable: .receivable
        case .payable: .payable
        }
    }

    var isLiability: Bool {
        self == .credit || self == .payable
    }
}

enum TransactionKind: String, CaseIterable, Codable, Identifiable {
    case expense, income, transfer, exchange, adjustment

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        case .exchange: "换汇"
        case .adjustment: "调整"
        }
    }
}

enum CategoryKind: String, Codable { case expense, income }
enum AdjustmentDirection: String, CaseIterable, Codable, Identifiable {
    case increase, decrease
    var id: String { rawValue }
    var title: String { self == .increase ? "增加" : "减少" }
}
enum ExchangeRateSource: String, Codable { case manual, remote }
