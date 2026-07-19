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
