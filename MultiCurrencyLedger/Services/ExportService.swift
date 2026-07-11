import Foundation

enum ExportService {
    static func makeJSONBackup(
        accounts: [Account],
        wallets: [CurrencyWallet],
        transactions: [LedgerTransaction],
        categories: [LedgerCategory],
        rates: [ExchangeRate],
        budgets: [MonthlyBudget] = [],
        baseCurrencyCode: String
    ) throws -> URL {
        let backup = BackupDTO(
            version: 2,
            exportedAt: .now,
            settings: .init(baseCurrencyCode: baseCurrencyCode),
            accounts: accounts.map(AccountDTO.init),
            wallets: wallets.map(WalletDTO.init),
            categories: categories.map(CategoryDTO.init),
            transactions: transactions.map(TransactionDTO.init),
            exchangeRates: rates.map(ExchangeRateDTO.init),
            monthlyBudgets: budgets.map(MonthlyBudgetDTO.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let url = temporaryURL(extension: "json", prefix: "MultiCurrencyLedger-Backup")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func makeCSV(transactions: [LedgerTransaction]) throws -> URL {
        let headers = [
            "日期", "交易类型", "账户", "来源币种", "来源金额",
            "目标账户", "目标币种", "目标金额", "分类", "手续费", "手续费币种", "备注"
        ]
        let formatter = ISO8601DateFormatter()
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                formatter.string(from: transaction.date),
                transaction.type.rawValue,
                transaction.sourceAccount?.name ?? "",
                transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "",
                decimalString(transaction.sourceAmount ?? transaction.amount),
                transaction.destinationAccount?.name ?? "",
                transaction.destinationCurrencyCode ?? "",
                decimalString(transaction.destinationAmount),
                transaction.category?.name ?? "",
                decimalString(transaction.feeAmount),
                transaction.feeCurrencyCode ?? "",
                transaction.note ?? ""
            ].map(csvField).joined(separator: ",")
        }
        let csv = ([headers.map(csvField).joined(separator: ",")] + rows).joined(separator: "\r\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        guard let content = csv.data(using: .utf8) else { throw ExportError.encodingFailed }
        data.append(content)
        let url = temporaryURL(extension: "csv", prefix: "MultiCurrencyLedger-Transactions")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func csvField(_ value: String) -> String {
        let safeValue: String
        if let first = value.first, ["=", "+", "-", "@"].contains(first) {
            safeValue = "'" + value
        } else {
            safeValue = value
        }
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func decimalString(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    private static func temporaryURL(extension fileExtension: String, prefix: String) -> URL {
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(date).\(fileExtension)")
    }
}

enum ExportError: LocalizedError {
    case encodingFailed
    var errorDescription: String? { "无法编码导出文件" }
}

private struct BackupDTO: Codable {
    let version: Int
    let exportedAt: Date
    let settings: SettingsDTO
    let accounts: [AccountDTO]
    let wallets: [WalletDTO]
    let categories: [CategoryDTO]
    let transactions: [TransactionDTO]
    let exchangeRates: [ExchangeRateDTO]
    let monthlyBudgets: [MonthlyBudgetDTO]
}

private struct SettingsDTO: Codable { let baseCurrencyCode: String }

private struct AccountDTO: Codable {
    let id: UUID
    let name: String
    let type: String
    let note: String?
    let isHidden: Bool
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let walletIDs: [UUID]

    init(_ value: Account) {
        id = value.id; name = value.name; type = value.typeRawValue; note = value.note
        isHidden = value.isHidden; sortOrder = value.sortOrder
        createdAt = value.createdAt; updatedAt = value.updatedAt
        walletIDs = value.wallets.map(\.id)
    }
}

private struct WalletDTO: Codable {
    let id: UUID
    let accountID: UUID?
    let currencyCode: String
    let balance: Decimal
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ value: CurrencyWallet) {
        id = value.id; accountID = value.account?.id; currencyCode = value.currencyCode
        balance = value.balance; isEnabled = value.isEnabled
        createdAt = value.createdAt; updatedAt = value.updatedAt
    }
}

private struct CategoryDTO: Codable {
    let id: UUID
    let name: String
    let type: String
    let symbolName: String
    let sortOrder: Int
    let isSystem: Bool

    init(_ value: LedgerCategory) {
        id = value.id; name = value.name; type = value.typeRawValue
        symbolName = value.symbolName; sortOrder = value.sortOrder; isSystem = value.isSystem
    }
}

private struct TransactionDTO: Codable {
    let id: UUID
    let type: String
    let date: Date
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let amount: Decimal?
    let currencyCode: String?
    let sourceAccountID: UUID?
    let sourceWalletID: UUID?
    let destinationAccountID: UUID?
    let destinationWalletID: UUID?
    let sourceAmount: Decimal?
    let sourceCurrencyCode: String?
    let destinationAmount: Decimal?
    let destinationCurrencyCode: String?
    let feeAmount: Decimal?
    let feeCurrencyCode: String?
    let feeWalletID: UUID?
    let exchangeRate: Decimal?
    let adjustmentDirection: String?
    let adjustmentReason: String?
    let categoryID: UUID?

    init(_ value: LedgerTransaction) {
        id = value.id; type = value.typeRawValue; date = value.date; note = value.note
        createdAt = value.createdAt; updatedAt = value.updatedAt
        amount = value.amount; currencyCode = value.currencyCode
        sourceAccountID = value.sourceAccount?.id; sourceWalletID = value.sourceWallet?.id
        destinationAccountID = value.destinationAccount?.id; destinationWalletID = value.destinationWallet?.id
        sourceAmount = value.sourceAmount; sourceCurrencyCode = value.sourceCurrencyCode
        destinationAmount = value.destinationAmount; destinationCurrencyCode = value.destinationCurrencyCode
        feeAmount = value.feeAmount; feeCurrencyCode = value.feeCurrencyCode; feeWalletID = value.feeWallet?.id
        exchangeRate = value.exchangeRate; adjustmentDirection = value.adjustmentDirectionRawValue
        adjustmentReason = value.adjustmentReason; categoryID = value.category?.id
    }
}

private struct ExchangeRateDTO: Codable {
    let id: UUID
    let currencyCode: String
    let baseCurrencyCode: String
    let rate: Decimal
    let source: String
    let updatedAt: Date

    init(_ value: ExchangeRate) {
        id = value.id; currencyCode = value.currencyCode; baseCurrencyCode = value.baseCurrencyCode
        rate = value.rate; source = value.sourceRawValue; updatedAt = value.updatedAt
    }
}

private struct MonthlyBudgetDTO: Codable {
    let id: UUID
    let bookID: UUID
    let monthStart: Date
    let currencyCode: String
    let amount: Decimal
    let createdAt: Date
    let updatedAt: Date

    init(_ value: MonthlyBudget) {
        id = value.id; bookID = value.bookID; monthStart = value.monthStart
        currencyCode = value.currencyCode; amount = value.amount
        createdAt = value.createdAt; updatedAt = value.updatedAt
    }
}
