import XCTest

final class MultiCurrencyLedgerSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOME_SAMPLE_DATA"] = "1"
        app.launchEnvironment["APP_PREVIEW_LANGUAGE"] = "zh-Hans"
        app.launch()
    }

    func testLaunchAndFourRootTabs() {
        assertTab("ledger", marker: app.buttons["root-entry-button"])
        assertTab("assets", marker: app.navigationBars["资产"])
        assertTab("savings", marker: app.navigationBars["计划"])
        assertTab("statistics", marker: app.navigationBars["统计"])
    }

    func testEntryCategorySublayerAndActionPanel() {
        app.buttons["root-entry-button"].tap()
        XCTAssertTrue(app.staticTexts["支出"].waitForExistence(timeout: 3))

        let dining = app.buttons["餐饮"].firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 3))
        dining.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["修改"].waitForExistence(timeout: 2))
        app.buttons["取消"].tap()

        dining.tap()
        XCTAssertTrue(app.buttons["新分类"].waitForExistence(timeout: 2))
    }

    func testBillSwipeAndAssetDetail() {
        app.buttons["root-tab-ledger"].tap()
        app.swipeLeft()
        app.swipeRight()
        XCTAssertTrue(app.buttons["root-tab-ledger"].exists)

        app.buttons["root-tab-assets"].tap()
        let account = app.staticTexts["日常账户"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()
        XCTAssertTrue(app.navigationBars["日常账户"].waitForExistence(timeout: 3))
    }

    func testBillSearchClosesBackToCollapsedButton() {
        app.buttons["root-tab-ledger"].tap()
        let collapsedSearch = app.buttons["搜索当前月账单"]
        XCTAssertTrue(collapsedSearch.waitForExistence(timeout: 3))
        collapsedSearch.tap()

        let field = app.textFields["搜索当前月"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("餐饮")
        app.buttons["关闭搜索"].tap()

        XCTAssertTrue(collapsedSearch.waitForExistence(timeout: 2))
        XCTAssertFalse(field.exists)
    }

    func testAssetModulesDoNotShowItemCount() {
        app.buttons["root-tab-assets"].tap()
        XCTAssertTrue(app.navigationBars["资产"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["0 项"].exists)
    }

    func testPlanReminderCompletion() {
        app.buttons["root-tab-savings"].tap()
        let complete = app.buttons["标记为已完成"].firstMatch
        let reopen = app.buttons["恢复未完成"].firstMatch
        XCTAssertTrue(
            complete.waitForExistence(timeout: 3) || reopen.waitForExistence(timeout: 1),
            "Expected a seeded repayment reminder completion control"
        )
        (complete.exists ? complete : reopen).tap()
    }

    private func assertTab(_ identifier: String, marker: XCUIElement) {
        let tab = app.buttons["root-tab-\(identifier)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
    }
}
