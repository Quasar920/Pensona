import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRegionalDefaultAndPersistence() {
        defaults.set("dark", forKey: AppPreferences.appearanceKey)
        let chinese = AppPreferences(defaults: defaults, regionCode: "CN")
        XCTAssertEqual(chinese.appearance, .light)
        XCTAssertEqual(chinese.amountColorConvention, .expenseGreenIncomeRed)
        XCTAssertTrue(chinese.hapticsEnabled)

        chinese.hapticsEnabled = false
        chinese.amountColorConvention = .expenseRedIncomeGreen
        chinese.language = .japanese

        let restored = AppPreferences(defaults: defaults, regionCode: "CN")
        XCTAssertEqual(restored.appearance, .light)
        XCTAssertFalse(restored.hapticsEnabled)
        XCTAssertEqual(restored.amountColorConvention, .expenseRedIncomeGreen)
        XCTAssertEqual(restored.language, .japanese)
        XCTAssertEqual(restored.locale.identifier, "ja")
    }

    func testNonChineseRegionDefaultsToRedExpenses() {
        XCTAssertEqual(
            AppPreferences(defaults: defaults, regionCode: "US").amountColorConvention,
            .expenseRedIncomeGreen
        )
    }

    func testSystemLanguageRemainsSystemResponsive() {
        let preferences = AppPreferences(defaults: defaults, regionCode: "US")
        preferences.language = .system

        let restored = AppPreferences(defaults: defaults, regionCode: "US")
        XCTAssertEqual(restored.language, .system)
        XCTAssertEqual(restored.locale, Locale.autoupdatingCurrent)
    }

    func testBothAmountConventionsMatchTransactionSemanticRoles() {
        XCTAssertEqual(
            AmountSemanticStyle.color(for: .expense, convention: .expenseRedIncomeGreen),
            .red
        )
        XCTAssertEqual(
            AmountSemanticStyle.color(for: .income, convention: .expenseRedIncomeGreen),
            .green
        )
        XCTAssertEqual(
            AmountSemanticStyle.color(for: .expense, convention: .expenseGreenIncomeRed),
            .green
        )
        XCTAssertEqual(
            AmountSemanticStyle.color(for: .income, convention: .expenseGreenIncomeRed),
            .red
        )
    }

    func testGlassQualityDowngradesForEveryApprovedSignal() {
        XCTAssertEqual(GlassQualityController.quality(
            reduceTransparency: false,
            isLowPowerMode: false,
            thermalState: .nominal
        ), .full)
        XCTAssertEqual(GlassQualityController.quality(
            reduceTransparency: true,
            isLowPowerMode: false,
            thermalState: .nominal
        ), .simplified)
        XCTAssertEqual(GlassQualityController.quality(
            reduceTransparency: false,
            isLowPowerMode: true,
            thermalState: .nominal
        ), .simplified)
        XCTAssertEqual(GlassQualityController.quality(
            reduceTransparency: false,
            isLowPowerMode: false,
            thermalState: .serious
        ), .simplified)
    }
}
