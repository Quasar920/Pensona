import Foundation

enum MoneyFormatter {
    static func currencySymbol(currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = .current
        return formatter.currencySymbol ?? currencyCode
    }

    static func string(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = .current
        formatter.minimumFractionDigits = currencyCode == SupportedCurrency.JPY.rawValue ? 0 : 2
        formatter.maximumFractionDigits = formatter.minimumFractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }

    static func plain(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currencyCode == SupportedCurrency.JPY.rawValue ? 0 : 2
        formatter.maximumFractionDigits = formatter.minimumFractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func compactString(_ amount: Decimal, currencyCode: String) -> String {
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
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.locale = .current
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
            return formatter.string(from: amount as NSDecimalNumber)
                ?? currencySymbol(currencyCode: currencyCode) + "\(amount)"
        }

        let scaled = amount / unit.divisor
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: scaled as NSDecimalNumber) ?? "\(scaled)"
        return currencySymbol(currencyCode: currencyCode) + number + unit.suffix
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
