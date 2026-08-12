import Foundation

enum URLDraftError: LocalizedError, Equatable {
    case unsupportedRoute
    case unknownParameter(String)
    case duplicateParameter(String)
    case missingParameter(String)
    case invalidType
    case invalidAmount
    case invalidDate
    case invalidReference(String)
    case ambiguousReference(String)
    case crossBookReference

    var errorDescription: String? {
        switch self {
        case .unsupportedRoute: AppLocalization.string("brand.error.unsupportedURL")
        case let .unknownParameter(name): AppLocalization.string( "链接包含不支持的参数：\(name)")
        case let .duplicateParameter(name): AppLocalization.string( "链接参数重复：\(name)")
        case let .missingParameter(name): AppLocalization.string( "链接缺少必填参数：\(name)")
        case .invalidType: AppLocalization.string( "链接中的交易类型无效")
        case .invalidAmount: AppLocalization.string( "链接中的金额无效")
        case .invalidDate: AppLocalization.string( "链接中的日期无效")
        case let .invalidReference(name): AppLocalization.string( "找不到链接指定的\(name)")
        case let .ambiguousReference(name): AppLocalization.string( "链接指定的\(name)不唯一，请改用 UUID")
        case .crossBookReference: AppLocalization.string( "链接不能引用其他账本的数据")
        }
    }
}

struct URLDraftRequest: Equatable {
    let type: TransactionKind
    let amount: Decimal
    let currencyCode: String?
    let bookSelector: String?
    let sourceWalletSelector: String
    let destinationWalletSelector: String?
    let destinationAmount: Decimal?
    let feeAmount: Decimal?
    let feeWalletSelector: String?
    let categorySelector: String?
    let merchantOrCounterparty: String?
    let note: String?
    let date: Date
    let adjustmentDirection: AdjustmentDirection?
    let adjustmentReason: String?
}

struct URLDraftParser {
    static let scheme = "multiledger"
    static let host = "entry"

    private let allowedKeys: Set<String> = [
        "type", "amount", "currency", "book", "wallet", "destinationWallet",
        "destinationAmount", "fee", "feeWallet", "category",
        "merchant", "note", "date", "adjustmentDirection", "adjustmentReason"
    ]

    func parse(_ url: URL, now: Date = .now) throws -> URLDraftRequest {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host?.lowercased() == Self.host,
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLDraftError.unsupportedRoute
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard allowedKeys.contains(item.name) else {
                throw URLDraftError.unknownParameter(item.name)
            }
            guard values[item.name] == nil else {
                throw URLDraftError.duplicateParameter(item.name)
            }
            values[item.name] = item.value ?? ""
        }

        let typeText = try required("type", values: values)
        guard let type = TransactionKind(rawValue: typeText.lowercased()) else {
            throw URLDraftError.invalidType
        }
        let amount = try positiveDecimal("amount", values: values)
        let wallet = try required("wallet", values: values)
        let destinationAmount = try optionalPositiveDecimal("destinationAmount", values: values)
        let fee = try optionalPositiveDecimal("fee", values: values)
        let date = try parseDate(values["date"], fallback: now)
        let direction: AdjustmentDirection?
        if let raw = values["adjustmentDirection"], !raw.isEmpty {
            guard let parsed = AdjustmentDirection(rawValue: raw.lowercased()) else {
                throw URLDraftError.invalidType
            }
            direction = parsed
        } else {
            direction = nil
        }
        return URLDraftRequest(
            type: type,
            amount: amount,
            currencyCode: values["currency"]?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().nilIfEmpty,
            bookSelector: values["book"]?.trimmed.nilIfEmpty,
            sourceWalletSelector: wallet,
            destinationWalletSelector: values["destinationWallet"]?.trimmed.nilIfEmpty,
            destinationAmount: destinationAmount,
            feeAmount: fee,
            feeWalletSelector: values["feeWallet"]?.trimmed.nilIfEmpty,
            categorySelector: values["category"]?.trimmed.nilIfEmpty,
            merchantOrCounterparty: values["merchant"]?.trimmed.nilIfEmpty,
            note: values["note"]?.trimmed.nilIfEmpty,
            date: date,
            adjustmentDirection: direction,
            adjustmentReason: values["adjustmentReason"]?.trimmed.nilIfEmpty
        )
    }

    private func required(_ key: String, values: [String: String]) throws -> String {
        guard let value = values[key]?.trimmed, !value.isEmpty else {
            throw URLDraftError.missingParameter(key)
        }
        return value
    }

    private func positiveDecimal(_ key: String, values: [String: String]) throws -> Decimal {
        guard let value = values[key], let amount = DecimalParser.parse(value), amount > 0 else {
            throw URLDraftError.invalidAmount
        }
        return amount
    }

    private func optionalPositiveDecimal(_ key: String, values: [String: String]) throws -> Decimal? {
        guard let value = values[key] else { return nil }
        guard let amount = DecimalParser.parse(value), amount > 0 else {
            throw URLDraftError.invalidAmount
        }
        return amount
    }

    private func parseDate(_ value: String?, fallback: Date) throws -> Date {
        guard let value, !value.isEmpty else { return fallback }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        guard let date = day.date(from: value) else { throw URLDraftError.invalidDate }
        return date
    }
}

struct URLDraftResolver {
    func resolve(
        _ request: URLDraftRequest,
        books: [LedgerBook],
        wallets: [CurrencyWallet],
        categories: [LedgerCategory],
        preferredBookID: UUID? = nil
    ) throws -> TransactionDraft {
        let book = try resolveBook(
            selector: request.bookSelector,
            books: books,
            preferredBookID: preferredBookID
        )
        let scopedWallets = wallets.filter {
            $0.isEnabled && $0.account?.isArchived == false
        }
        let source = try resolveWallet(
            selector: request.sourceWalletSelector,
            currencyCode: request.currencyCode,
            wallets: scopedWallets,
            label: "来源钱包"
        )
        let destination: CurrencyWallet?
        if let selector = request.destinationWalletSelector {
            destination = try resolveWallet(
                selector: selector,
                currencyCode: request.type == .transfer ? source.currencyCode : nil,
                wallets: scopedWallets,
                label: "目标钱包"
            )
        } else {
            destination = nil
        }
        let feeWallet: CurrencyWallet?
        if let selector = request.feeWalletSelector {
            feeWallet = try resolveWallet(
                selector: selector,
                currencyCode: nil,
                wallets: scopedWallets,
                label: "手续费钱包"
            )
        } else {
            feeWallet = request.feeAmount == nil ? nil : source
        }
        let expectedCategory: CategoryKind = request.type == .income ? .income : .expense
        let category = try request.categorySelector.map { selector in
            try resolveCategory(
                selector: selector,
                type: expectedCategory,
                bookID: book.id,
                categories: categories
            )
        }
        let draft = TransactionDraft(
            type: request.type,
            bookID: book.id,
            amount: request.amount,
            sourceWallet: source,
            destinationWallet: destination,
            destinationAmount: request.destinationAmount,
            feeAmount: request.feeAmount,
            feeWallet: feeWallet,
            date: request.date,
            note: request.note,
            merchantOrCounterparty: request.merchantOrCounterparty,
            category: request.type == .expense || request.type == .income ? category : nil,
            adjustmentDirection: request.type == .adjustment ? request.adjustmentDirection : nil,
            adjustmentReason: request.type == .adjustment ? request.adjustmentReason : nil
        )
        _ = try TransactionImpactCalculator().deltas(for: draft)
        return draft
    }

    private func resolveBook(
        selector: String?,
        books: [LedgerBook],
        preferredBookID: UUID?
    ) throws -> LedgerBook {
        if let selector {
            return try unique(
                books.filter { matches(selector, id: $0.id, name: $0.name) },
                label: "账本"
            )
        }
        if let preferredBookID, let preferred = books.first(where: { $0.id == preferredBookID }) {
            return preferred
        }
        return try unique(books, label: "账本")
    }

    private func resolveWallet(
        selector: String,
        currencyCode: String?,
        wallets: [CurrencyWallet],
        label: String
    ) throws -> CurrencyWallet {
        let matches = wallets.filter {
            self.matches(selector, id: $0.id, name: $0.account?.name ?? "")
                && (currencyCode == nil || $0.currencyCode == currencyCode)
        }
        return try unique(matches, label: label)
    }

    private func resolveCategory(
        selector: String,
        type: CategoryKind,
        bookID: UUID,
        categories: [LedgerCategory]
    ) throws -> LedgerCategory {
        try unique(categories.filter {
            !$0.isArchived
                && $0.type == type
                && matches(selector, id: $0.id, name: $0.name)
        }, label: "分类")
    }

    private func matches(_ selector: String, id: UUID, name: String) -> Bool {
        id.uuidString.caseInsensitiveCompare(selector) == .orderedSame
            || name.compare(
                selector,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: Locale.current
            ) == .orderedSame
    }

    private func unique<T>(_ values: [T], label: String) throws -> T {
        guard !values.isEmpty else { throw URLDraftError.invalidReference(label) }
        guard values.count == 1 else { throw URLDraftError.ambiguousReference(label) }
        return values[0]
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
