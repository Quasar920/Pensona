import Foundation

enum MoneyFormatter {
    private enum FormatterStyle: Hashable {
        case currency
        case decimal
    }

    private struct FormatterKey: Hashable {
        let style: FormatterStyle
        let localeIdentifier: String
        let currencyCode: String
        let minimumFractionDigits: Int?
        let maximumFractionDigits: Int?
    }

    /// `NumberFormatter` is mutable and not safe to share across threads. Keeping one cache
    /// per thread lets repeated row rendering reuse formatters without concurrent access.
    private final class ThreadFormatterCache: NSObject {
        var formatters: [FormatterKey: NumberFormatter] = [:]
    }

    private static let threadCacheKey = "MultiCurrencyLedger.MoneyFormatter.ThreadCache"

    static func currencySymbol(
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let normalizedCode = normalizedCurrencyCode(currencyCode)
        let formatter = formatter(
            style: .currency,
            currencyCode: normalizedCode,
            locale: locale
        )
        return formatter.currencySymbol ?? currencyCode
    }

    static func string(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .current,
        fractionDigits: Int? = nil
    ) -> String {
        let normalizedCode = normalizedCurrencyCode(currencyCode)
        let digits = resolvedFractionDigits(fractionDigits, currencyCode: normalizedCode)
        let formatter = formatter(
            style: .currency,
            currencyCode: normalizedCode,
            locale: locale,
            minimumFractionDigits: digits,
            maximumFractionDigits: digits
        )
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(normalizedCode) \(amount)"
    }

    static func plain(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .current,
        fractionDigits: Int? = nil
    ) -> String {
        let normalizedCode = normalizedCurrencyCode(currencyCode)
        let digits = resolvedFractionDigits(fractionDigits, currencyCode: normalizedCode)
        let formatter = formatter(
            style: .decimal,
            currencyCode: normalizedCode,
            locale: locale,
            minimumFractionDigits: digits,
            maximumFractionDigits: digits
        )
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func compactString(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let normalizedCode = normalizedCurrencyCode(currencyCode)
        let absoluteValue = abs((amount as NSDecimalNumber).doubleValue)
        let unit: (divisor: Decimal, suffix: String)?
        if absoluteValue >= 100_000_000 {
            unit = (100_000_000, "亿")
        } else if absoluteValue >= 10_000 {
            unit = (10_000, "万")
        } else {
            unit = nil
        }

        guard let unit else {
            let formatter = formatter(
                style: .currency,
                currencyCode: normalizedCode,
                locale: locale,
                minimumFractionDigits: 0,
                maximumFractionDigits: 0
            )
            return formatter.string(from: amount as NSDecimalNumber)
                ?? currencySymbol(currencyCode: normalizedCode, locale: locale) + "\(amount)"
        }

        let scaled = amount / unit.divisor
        let formatter = formatter(
            style: .decimal,
            currencyCode: normalizedCode,
            locale: locale,
            minimumFractionDigits: 0,
            maximumFractionDigits: 1
        )
        let number = formatter.string(from: scaled as NSDecimalNumber) ?? "\(scaled)"
        return currencySymbol(currencyCode: normalizedCode, locale: locale) + number + unit.suffix
    }

    private static func formatter(
        style: FormatterStyle,
        currencyCode: String,
        locale: Locale,
        minimumFractionDigits: Int? = nil,
        maximumFractionDigits: Int? = nil
    ) -> NumberFormatter {
        let key = FormatterKey(
            style: style,
            localeIdentifier: locale.identifier,
            currencyCode: currencyCode,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        let dictionary = Thread.current.threadDictionary
        let cache: ThreadFormatterCache
        if let existing = dictionary[threadCacheKey] as? ThreadFormatterCache {
            cache = existing
        } else {
            cache = ThreadFormatterCache()
            dictionary[threadCacheKey] = cache
        }

        if let cached = cache.formatters[key] {
            return cached
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        switch style {
        case .currency:
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
        case .decimal:
            formatter.numberStyle = .decimal
        }
        if let minimumFractionDigits {
            formatter.minimumFractionDigits = minimumFractionDigits
        }
        if let maximumFractionDigits {
            formatter.maximumFractionDigits = maximumFractionDigits
        }
        cache.formatters[key] = formatter
        return formatter
    }

    private static func normalizedCurrencyCode(_ currencyCode: String) -> String {
        currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func resolvedFractionDigits(_ override: Int?, currencyCode: String) -> Int {
        min(max(override ?? SupportedCurrency.fractionDigits(for: currencyCode), 0), 20)
    }
}

enum DecimalParser {
    static func parse(_ text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
