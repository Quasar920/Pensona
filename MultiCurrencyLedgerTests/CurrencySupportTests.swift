import XCTest
@testable import MultiCurrencyLedger

final class CurrencySupportTests: XCTestCase {
    func testCurrencyCatalogContainsMoreThanFiftyISO4217Currencies() {
        XCTAssertGreaterThan(SupportedCurrency.allCases.count, 50)
        XCTAssertEqual(SupportedCurrency(rawValue: "CNY"), .CNY)
        XCTAssertEqual(SupportedCurrency(rawValue: "USD"), .USD)
    }

    func testZeroTwoAndThreeFractionDigitCurrencies() {
        XCTAssertEqual(SupportedCurrency.JPY.fractionDigits, 0)
        XCTAssertEqual(SupportedCurrency.CNY.fractionDigits, 2)
        XCTAssertEqual(SupportedCurrency.KWD.fractionDigits, 3)
        XCTAssertEqual(SupportedCurrency.fractionDigits(for: "unknown"), 2)
    }

    func testMoneyFormatterSeparatesLocaleCurrencyAndFractionDigitConfigurations() {
        let enUS = Locale(identifier: "en_US")
        let deDE = Locale(identifier: "de_DE")

        XCTAssertEqual(
            MoneyFormatter.plain(1_234.5, currencyCode: "USD", locale: enUS),
            "1,234.50"
        )
        XCTAssertEqual(
            MoneyFormatter.plain(1_234.5, currencyCode: "USD", locale: deDE),
            "1.234,50"
        )
        XCTAssertEqual(
            MoneyFormatter.plain(1_234, currencyCode: "JPY", locale: enUS),
            "1,234"
        )
        XCTAssertEqual(
            MoneyFormatter.plain(1.2, currencyCode: "KWD", locale: enUS),
            "1.200"
        )
        XCTAssertEqual(
            MoneyFormatter.plain(
                1.2,
                currencyCode: "USD",
                locale: enUS,
                fractionDigits: 4
            ),
            "1.2000"
        )

        XCTAssertEqual(
            MoneyFormatter.string(1_234.5, currencyCode: "usd", locale: enUS),
            "$1,234.50"
        )
    }

    func testSupportedCurrenciesUseReviewedStableSymbols() {
        let expected: [SupportedCurrency: String] = [
            .AED: "د.إ", .ARS: "AR$", .AUD: "A$", .BDT: "৳", .BGN: "лв",
            .BHD: "د.ب", .BRL: "R$", .CAD: "C$", .CHF: "CHF", .CLP: "CL$",
            .CNY: "¥", .COP: "COL$", .CZK: "Kč", .DKK: "kr", .EGP: "E£",
            .EUR: "€", .GBP: "£", .GEL: "₾", .GHS: "₵", .HKD: "HK$",
            .HUF: "Ft", .IDR: "Rp", .ILS: "₪", .INR: "₹", .ISK: "kr",
            .JOD: "د.ا", .JPY: "¥", .KES: "KSh", .KRW: "₩", .KWD: "د.ك",
            .KZT: "₸", .LKR: "Rs", .MAD: "د.م.", .MXN: "MX$", .MYR: "RM",
            .NGN: "₦", .NOK: "kr", .NZD: "NZ$", .OMR: "ر.ع.", .PEN: "S/",
            .PHP: "₱", .PKR: "Rs", .PLN: "zł", .QAR: "ر.ق", .RON: "lei",
            .RSD: "дин.", .RUB: "₽", .SAR: "\u{20C1}", .SEK: "kr", .SGD: "S$",
            .THB: "฿", .TND: "د.ت", .TRY: "₺", .TWD: "NT$", .UAH: "₴",
            .USD: "$", .UYU: "$U", .VND: "₫", .ZAR: "R"
        ]

        XCTAssertEqual(expected.count, SupportedCurrency.allCases.count)
        for currency in SupportedCurrency.allCases {
            XCTAssertEqual(currency.symbol, expected[currency], currency.rawValue)
            XCTAssertEqual(MoneyFormatter.currencySymbol(currencyCode: currency.rawValue), expected[currency])
        }

        XCTAssertEqual(Array(SupportedCurrency.CNY.symbol.unicodeScalars).map(\.value), [0x00A5])
        XCTAssertNotEqual(SupportedCurrency.CNY.symbol, "￥")
    }

    func testCurrencyFormattingUsesSymbolsInsteadOfLocaleQualifiedCodes() {
        let enUS = Locale(identifier: "en_US")
        let zhCN = Locale(identifier: "zh_CN")

        XCTAssertEqual(MoneyFormatter.string(88, currencyCode: "CNY", locale: enUS), "¥88.00")
        XCTAssertEqual(MoneyFormatter.string(88, currencyCode: "JPY", locale: zhCN), "¥88")
        XCTAssertEqual(MoneyFormatter.string(88, currencyCode: "USD", locale: zhCN), "$88.00")

        let expense = LedgerTransaction(type: .expense, amount: 88, currencyCode: "CNY")
        XCTAssertEqual(expense.summaryAmount, "−¥88.00")
    }

    func testMoneyFormatterRemainsStableUnderConcurrentFormatting() async {
        let outputs = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for index in 0..<240 {
                group.addTask {
                    switch index % 3 {
                    case 0:
                        "usd|" + MoneyFormatter.plain(
                            1_234.5,
                            currencyCode: "USD",
                            locale: Locale(identifier: "en_US")
                        )
                    case 1:
                        "jpy|" + MoneyFormatter.plain(
                            1_234,
                            currencyCode: "JPY",
                            locale: Locale(identifier: "en_US")
                        )
                    default:
                        "kwd|" + MoneyFormatter.plain(
                            1_234.5,
                            currencyCode: "KWD",
                            locale: Locale(identifier: "de_DE")
                        )
                    }
                }
            }

            var collected: [String] = []
            for await output in group {
                collected.append(output)
            }
            return collected
        }

        XCTAssertEqual(
            Set(outputs),
            ["usd|1,234.50", "jpy|1,234", "kwd|1.234,500"]
        )
    }
}
