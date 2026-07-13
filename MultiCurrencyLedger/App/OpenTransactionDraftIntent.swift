import AppIntents
import Foundation

enum ShortcutDraftType: String, AppEnum {
    case expense, income, transfer, exchange, adjustment

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "交易类型")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .expense: "支出",
        .income: "收入",
        .transfer: "转账",
        .exchange: "换汇",
        .adjustment: "调整"
    ]
}

struct OpenTransactionDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "打开待确认记账"
    static let description = IntentDescription("使用多币种账本自己的参数创建草稿，并在 App 中确认后入账。")
    static let openAppWhenRun = true

    @Parameter(title: "类型") var type: ShortcutDraftType
    @Parameter(title: "金额") var amount: Double
    @Parameter(title: "钱包名称或 UUID") var wallet: String
    @Parameter(title: "币种") var currency: String?
    @Parameter(title: "分类名称或 UUID") var category: String?
    @Parameter(title: "商户或交易对象") var merchant: String?
    @Parameter(title: "备注") var note: String?

    init() {}

    func perform() async throws -> some ProvidesDialog {
        guard amount > 0, amount.isFinite else { throw URLDraftError.invalidAmount }
        var components = URLComponents()
        components.scheme = URLDraftParser.scheme
        components.host = URLDraftParser.host
        var items = [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "amount", value: Self.amountString(amount)),
            URLQueryItem(name: "wallet", value: wallet)
        ]
        if let currency = currency?.trimmedForIntent { items.append(URLQueryItem(name: "currency", value: currency)) }
        if let category = category?.trimmedForIntent { items.append(URLQueryItem(name: "category", value: category)) }
        if let merchant = merchant?.trimmedForIntent { items.append(URLQueryItem(name: "merchant", value: merchant)) }
        if let note = note?.trimmedForIntent { items.append(URLQueryItem(name: "note", value: note)) }
        components.queryItems = items
        guard let url = components.url else { throw URLDraftError.unsupportedRoute }
        _ = try URLDraftParser().parse(url)
        UserDefaults.standard.set(url.absoluteString, forKey: URLDraftPendingRoute.defaultsKey)
        return .result(dialog: "请在 App 中确认交易信息")
    }

    private static func amountString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

enum URLDraftPendingRoute {
    static let defaultsKey = "pendingExternalTransactionDraftURL"
}

private extension String {
    var trimmedForIntent: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
