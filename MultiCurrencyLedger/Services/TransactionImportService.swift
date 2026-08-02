import CryptoKit
import Foundation
import SwiftData

enum TransactionImportField: String, CaseIterable, Identifiable {
    case date, type, amount, currency, account, category, merchant, note
    case destinationAccount, destinationAmount, destinationCurrency, fee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: AppLocalization.string( "日期")
        case .type: AppLocalization.string( "收支类型")
        case .amount: AppLocalization.string( "金额")
        case .currency: AppLocalization.string( "币种")
        case .account: AppLocalization.string( "账户")
        case .category: AppLocalization.string( "分类")
        case .merchant: AppLocalization.string( "商家/对方")
        case .note: AppLocalization.string( "备注")
        case .destinationAccount: AppLocalization.string( "目标账户")
        case .destinationAmount: AppLocalization.string( "目标金额")
        case .destinationCurrency: AppLocalization.string( "目标币种")
        case .fee: AppLocalization.string( "手续费")
        }
    }

    var isRequired: Bool { self == .amount }
}

struct TransactionImportMapping: Equatable {
    var columns: [TransactionImportField: Int] = [:]

    subscript(_ field: TransactionImportField) -> Int? {
        get { columns[field] }
        set { columns[field] = newValue }
    }

    static func suggested(headers: [String], preset: TransactionImportPreset) -> Self {
        var result = Self()
        for field in TransactionImportField.allCases {
            let aliases = aliases(for: field, preset: preset)
            result[field] = headers.firstIndex { header in
                aliases.contains(normalize(header))
            }
        }
        return result
    }

    private static func aliases(
        for field: TransactionImportField,
        preset: TransactionImportPreset
    ) -> Set<String> {
        var values: [String]
        switch field {
        case .date:
            values = ["日期", "时间", "交易时间", "交易日期", "创建时间", "date", "time", "datetime"]
        case .type:
            values = ["类型", "收支类型", "交易类型", "收支", "资金流向", "type", "direction"]
        case .amount:
            values = ["金额", "交易金额", "金额元", "收支金额", "商品金额", "amount", "money"]
        case .currency:
            values = ["币种", "货币", "currency", "currencycode"]
        case .account:
            values = ["账户", "支付方式", "付款方式", "支付账户", "当前状态", "account", "wallet"]
        case .category:
            values = ["分类", "一级分类", "二级分类", "交易分类", "category"]
        case .merchant:
            values = ["商家", "商户", "交易对方", "对方", "商品说明", "商品", "merchant", "counterparty"]
        case .note:
            values = ["备注", "说明", "备注信息", "note", "memo", "description"]
        case .destinationAccount:
            values = ["目标账户", "转入账户", "收款账户", "destinationaccount", "toaccount"]
        case .destinationAmount:
            values = ["目标金额", "转入金额", "换入金额", "destinationamount", "toamount"]
        case .destinationCurrency:
            values = ["目标币种", "转入币种", "换入币种", "destinationcurrency", "tocurrency"]
        case .fee:
            values = ["手续费", "服务费", "fee"]
        }
        switch preset {
        case .iCost:
            if field == .account { values.insert(contentsOf: ["账户1", "账户2"], at: 0) }
        case .alipay:
            if field == .amount { values.insert("金额元", at: 0) }
            if field == .merchant { values.insert(contentsOf: ["交易对方", "商品说明"], at: 0) }
        case .wechat:
            if field == .type { values.insert("收支类型", at: 0) }
            if field == .amount { values.insert("金额元", at: 0) }
        case .unionPay:
            if field == .account { values.insert("卡号", at: 0) }
        case .automatic, .generic:
            break
        }
        return Set(values.map(normalize))
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum TransactionImportRowStatus: Equatable {
    case ready
    case duplicate
    case invalid(String)

    var title: String {
        switch self {
        case .ready: AppLocalization.string( "可导入")
        case .duplicate: AppLocalization.string( "重复，已跳过")
        case .invalid(let reason): reason
        }
    }
}

struct TransactionImportPreviewRow: Identifiable {
    let id: Int
    let rawValues: [String]
    let summary: String
    let amount: Decimal?
    let currencyCode: String?
    let status: TransactionImportRowStatus
    let fingerprint: String?
    let draft: TransactionDraft?
}

struct TransactionImportPreview {
    let sourceName: String
    let preset: TransactionImportPreset
    let bookID: UUID
    let rows: [TransactionImportPreviewRow]

    var readyRows: [TransactionImportPreviewRow] { rows.filter { $0.status == .ready } }
    var duplicateCount: Int { rows.filter { $0.status == .duplicate }.count }
    var errorCount: Int {
        rows.filter { if case .invalid = $0.status { true } else { false } }.count
    }
}

enum TransactionImportError: LocalizedError, Equatable {
    case missingAmountMapping
    case missingBook
    case missingDefaultWallet
    case noValidRows
    case alreadyUndone

    var errorDescription: String? {
        switch self {
        case .missingAmountMapping: AppLocalization.string( "请至少映射金额列")
        case .missingBook: AppLocalization.string( "请选择导入账本")
        case .missingDefaultWallet: AppLocalization.string( "请选择默认钱包，或确保每一行都能匹配账户")
        case .noValidRows: AppLocalization.string( "没有可导入的新流水")
        case .alreadyUndone: AppLocalization.string( "这个导入批次已经撤销")
        }
    }
}

@MainActor
final class TransactionImportService {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func preview(
        table: SpreadsheetTable,
        sourceName: String,
        preset: TransactionImportPreset,
        mapping: TransactionImportMapping,
        bookID: UUID,
        defaultWallet: CurrencyWallet?,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory],
        existingFingerprints: [TransactionImportFingerprint]
    ) throws -> TransactionImportPreview {
        guard mapping[.amount] != nil else { throw TransactionImportError.missingAmountMapping }
        do {
            _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        } catch LedgerError.missingBook {
            throw TransactionImportError.missingBook
        }
        let scopedWallets = wallets.filter {
            $0.isEnabled && $0.account?.isArchived == false
        }
        let scopedCategories = categories.filter {
            !$0.isArchived
        }
        let existing = Set(existingFingerprints.map(\.value))
        var seen = Set<String>()
        let rows = table.rows.enumerated().map { offset, values in
            parseRow(
                line: offset + 2,
                values: values,
                mapping: mapping,
                bookID: bookID,
                defaultWallet: defaultWallet,
                wallets: scopedWallets,
                categories: scopedCategories,
                existing: existing,
                seen: &seen
            )
        }
        return TransactionImportPreview(
            sourceName: sourceName,
            preset: preset,
            bookID: bookID,
            rows: rows
        )
    }

    @discardableResult
    func commit(_ preview: TransactionImportPreview) throws -> TransactionImportBatch {
        let ready = preview.readyRows
        guard !ready.isEmpty else { throw TransactionImportError.noValidRows }
        let batch = TransactionImportBatch(
            sourceName: preview.sourceName,
            preset: preview.preset,
            bookID: preview.bookID,
            rowCount: preview.rows.count,
            importedCount: ready.count,
            skippedCount: preview.duplicateCount,
            errorCount: preview.errorCount
        )
        let drafts = ready.compactMap(\.draft)
        _ = try LedgerService(context: context).createBatch(drafts, bookID: preview.bookID) { transactions in
            context.insert(batch)
            for (row, transaction) in zip(ready, transactions) {
                guard let value = row.fingerprint else { continue }
                context.insert(TransactionImportFingerprint(
                    value: value,
                    batchID: batch.id,
                    transactionID: transaction.id
                ))
            }
        }
        return batch
    }

    func undo(
        _ batch: TransactionImportBatch,
        transactions: [LedgerTransaction],
        fingerprints: [TransactionImportFingerprint]
    ) throws {
        guard batch.undoneAt == nil else { throw TransactionImportError.alreadyUndone }
        let links = fingerprints.filter { $0.batchID == batch.id }
        let ids = Set(links.map(\.transactionID))
        let importedTransactions = transactions.filter { ids.contains($0.id) }
        let finish = {
            for link in links { self.context.delete(link) }
            batch.undoneAt = .now
        }
        if importedTransactions.isEmpty {
            finish()
            try context.save()
        } else {
            try LedgerService(context: context).deleteTransactions(
                importedTransactions,
                configureBeforeSave: finish
            )
        }
    }

    private func parseRow(
        line: Int,
        values: [String],
        mapping: TransactionImportMapping,
        bookID: UUID,
        defaultWallet: CurrencyWallet?,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory],
        existing: Set<String>,
        seen: inout Set<String>
    ) -> TransactionImportPreviewRow {
        func value(_ field: TransactionImportField) -> String {
            guard let index = mapping[field], values.indices.contains(index) else { return "" }
            return values[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let signedAmount = Self.parseAmount(value(.amount)), signedAmount != 0 else {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行金额无效"))
        }
        let amount = abs(signedAmount)
        let rawType = value(.type)
        guard let kind = Self.parseKind(rawType, signedAmount: signedAmount) else {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行无法识别收支类型"))
        }
        let requestedCurrency = Self.parseCurrency(value(.currency))
        if !value(.currency).isEmpty, requestedCurrency == nil {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行币种不受支持"))
        }
        guard let sourceWallet = Self.matchWallet(
            name: value(.account),
            currencyCode: requestedCurrency,
            wallets: wallets,
            fallback: defaultWallet
        ) else {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行找不到可用账户钱包"))
        }
        let date: Date
        if value(.date).isEmpty {
            date = .now
        } else if let parsed = Self.parseDate(value(.date)) {
            date = parsed
        } else {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行日期格式无效"))
        }
        let category = Self.matchCategory(value(.category), kind: kind, categories: categories)
        if !value(.category).isEmpty, category == nil, (kind == .expense || kind == .income) {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行找不到同类型分类"))
        }

        var destinationWallet: CurrencyWallet?
        var destinationAmount: Decimal?
        if kind == .transfer || kind == .exchange {
            let destinationCurrency = Self.parseCurrency(value(.destinationCurrency))
            destinationWallet = Self.matchWallet(
                name: value(.destinationAccount),
                currencyCode: destinationCurrency,
                wallets: wallets,
                fallback: nil
            )
            guard destinationWallet != nil else {
                return invalidRow(line, values, AppLocalization.string("第 \(line) 行缺少目标账户"))
            }
            if kind == .exchange {
                destinationAmount = Self.parseAmount(value(.destinationAmount)).map(abs)
                guard destinationAmount != nil else {
                    return invalidRow(line, values, AppLocalization.string("第 \(line) 行缺少换入金额"))
                }
            }
        }
        let fee = Self.parseAmount(value(.fee)).map(abs).flatMap { $0 > 0 ? $0 : nil }
        let note = value(.note).isEmpty ? nil : value(.note)
        let merchant = value(.merchant).isEmpty ? nil : value(.merchant)
        let draft = TransactionDraft(
            type: kind,
            amount: amount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            destinationAmount: destinationAmount,
            feeAmount: fee,
            feeWallet: fee == nil ? nil : sourceWallet,
            date: date,
            note: note,
            merchantOrCounterparty: merchant,
            category: category
        )
        do {
            _ = try TransactionImpactCalculator().deltas(for: draft)
        } catch {
            return invalidRow(line, values, AppLocalization.string("第 \(line) 行：\(error.localizedDescription)"))
        }
        let fingerprint = Self.fingerprint(
            bookID: bookID,
            draft: draft,
            categoryName: category?.name
        )
        let duplicate = existing.contains(fingerprint) || !seen.insert(fingerprint).inserted
        return TransactionImportPreviewRow(
            id: line,
            rawValues: values,
            summary: merchant ?? note ?? category?.name ?? kind.title,
            amount: amount,
            currencyCode: sourceWallet.currencyCode,
            status: duplicate ? .duplicate : .ready,
            fingerprint: fingerprint,
            draft: draft
        )
    }

    private func invalidRow(_ line: Int, _ values: [String], _ reason: String) -> TransactionImportPreviewRow {
        TransactionImportPreviewRow(
            id: line,
            rawValues: values,
            summary: "第 \(line) 行",
            amount: nil,
            currencyCode: nil,
            status: .invalid(reason),
            fingerprint: nil,
            draft: nil
        )
    }

    static func parseAmount(_ raw: String) -> Decimal? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let parenthesized = value.hasPrefix("(") && value.hasSuffix(")")
        value = value.replacingOccurrences(of: #"[^0-9,\.\-+]"#, with: "", options: .regularExpression)
        let comma = value.lastIndex(of: ",")
        let dot = value.lastIndex(of: ".")
        if let comma, let dot {
            if comma > dot {
                value = value.replacingOccurrences(of: ".", with: "")
                value = value.replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma {
            let decimals = value.distance(from: comma, to: value.endIndex) - 1
            value = decimals == 3
                ? value.replacingOccurrences(of: ",", with: "")
                : value.replacingOccurrences(of: ",", with: ".")
        }
        guard var amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if parenthesized { amount = -abs(amount) }
        return amount
    }

    static func parseDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        if let result = iso.date(from: value) { return result }
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd", "yyyy年MM月dd日 HH:mm:ss",
            "yyyy年MM月dd日"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            if let result = formatter.date(from: value) { return result }
        }
        return nil
    }

    private static func parseKind(_ raw: String, signedAmount: Decimal) -> TransactionKind? {
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return signedAmount < 0 ? .expense : .expense }
        if value.contains("支出") || value.contains("付款") || value == "expense" || value.contains("debit") { return .expense }
        if value.contains("收入") || value.contains("收款") || value == "income" || value.contains("credit") { return .income }
        if value.contains("换汇") || value.contains("兑换") || value == "exchange" { return .exchange }
        if value.contains("转账") || value == "transfer" { return .transfer }
        return nil
    }

    private static func parseCurrency(_ raw: String) -> String? {
        let value = raw.uppercased()
        if value.isEmpty { return nil }
        return SupportedCurrency.allCases.first { currency in
            value.contains(currency.rawValue) || value.contains(currency.localizedName.uppercased())
        }?.rawValue
    }

    private static func matchWallet(
        name: String,
        currencyCode: String?,
        wallets: [CurrencyWallet],
        fallback: CurrencyWallet?
    ) -> CurrencyWallet? {
        let cleanName = normalize(name)
        if !cleanName.isEmpty {
            if let exact = wallets.first(where: {
                normalize($0.account?.name ?? "") == cleanName
                    && (currencyCode == nil || $0.currencyCode == currencyCode)
            }) { return exact }
            if let fuzzy = wallets.first(where: {
                let accountName = normalize($0.account?.name ?? "")
                return (accountName.contains(cleanName) || cleanName.contains(accountName))
                    && (currencyCode == nil || $0.currencyCode == currencyCode)
            }) { return fuzzy }
        }
        if let fallback,
           wallets.contains(where: { $0.id == fallback.id }),
           currencyCode == nil || fallback.currencyCode == currencyCode {
            return fallback
        }
        if let currencyCode {
            let matches = wallets.filter { $0.currencyCode == currencyCode }
            if matches.count == 1 { return matches[0] }
        }
        return nil
    }

    private static func matchCategory(
        _ name: String,
        kind: TransactionKind,
        categories: [LedgerCategory]
    ) -> LedgerCategory? {
        guard kind == .expense || kind == .income else { return nil }
        let clean = normalize(name)
        guard !clean.isEmpty else { return nil }
        let expected: CategoryKind = kind == .expense ? .expense : .income
        return categories.first {
            $0.type == expected && normalize($0.name) == clean
        } ?? categories.first {
            $0.type == expected && (normalize($0.name).contains(clean) || clean.contains(normalize($0.name)))
        }
    }

    private static func fingerprint(
        bookID: UUID,
        draft: TransactionDraft,
        categoryName: String?
    ) -> String {
        let fields = [
            bookID.uuidString.lowercased(), draft.type.rawValue,
            String(Int(draft.date.timeIntervalSince1970)),
            NSDecimalNumber(decimal: draft.amount).stringValue,
            draft.sourceWallet?.id.uuidString.lowercased() ?? "",
            draft.destinationWallet?.id.uuidString.lowercased() ?? "",
            draft.destinationAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            categoryName ?? "", normalize(draft.merchantOrCounterparty ?? ""),
            normalize(draft.note ?? "")
        ]
        return SHA256.hash(data: Data(fields.joined(separator: "|").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
