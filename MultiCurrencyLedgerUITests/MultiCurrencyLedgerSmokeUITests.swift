import XCTest

final class MultiCurrencyLedgerSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOME_SAMPLE_DATA"] = "1"
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["APP_PREVIEW_LANGUAGE"] = "zh-Hans"
        app.launch()
        waitForDataReady()
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

    func testEntryContextGeniePanelsOpenAndClose() {
        app.buttons["root-entry-button"].tap()
        XCTAssertTrue(app.staticTexts["支出"].waitForExistence(timeout: 3))

        for (tag, title) in [
            ("AA", "AA 分摊"),
            ("组合支付", "组合支付"),
            ("优惠", "优惠")
        ] {
            let tagButton = app.buttons[tag].firstMatch
            XCTAssertTrue(tagButton.waitForExistence(timeout: 3))
            tagButton.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))

            let cancelButton = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
            cancelButton.tap()
            XCTAssertTrue(cancelButton.waitForNonExistence(timeout: 2))
        }
    }

    func testEntryContextSourceTagStaysVisibleAndCancelsPanel() {
        app.buttons["root-entry-button"].tap()
        XCTAssertTrue(app.staticTexts["支出"].waitForExistence(timeout: 3))

        app.buttons["entry-context-tag-aa"].tap()
        XCTAssertTrue(app.staticTexts["AA 分摊"].waitForExistence(timeout: 2))

        let sourceTag = app.buttons["entry-context-source-tag-aa"]
        XCTAssertTrue(sourceTag.waitForExistence(timeout: 2))
        sourceTag.tap()

        XCTAssertTrue(sourceTag.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["entry-context-tag-aa"].waitForExistence(timeout: 2))
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

    func testBillSearchCollapsesWhenKeyboardDismisses() {
        app.buttons["root-tab-ledger"].tap()
        let collapsedSearch = app.buttons["搜索当前月账单"]
        XCTAssertTrue(collapsedSearch.waitForExistence(timeout: 3))
        collapsedSearch.tap()

        let field = app.textFields["搜索当前月"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let chineseSubmit = app.keyboards.buttons["搜索"]
        let englishSubmit = app.keyboards.buttons["Search"]
        XCTAssertTrue(chineseSubmit.exists || englishSubmit.exists)
        (chineseSubmit.exists ? chineseSubmit : englishSubmit).tap()

        XCTAssertTrue(collapsedSearch.waitForExistence(timeout: 3))
        XCTAssertFalse(field.exists)
    }

    func testTransactionDetailExposesInlineActions() {
        app.buttons["root-tab-ledger"].tap()

        let diningTransaction = app.descendants(matching: .any)["sample-transaction-dining"].firstMatch
        XCTAssertTrue(diningTransaction.waitForExistence(timeout: 3))
        diningTransaction.tap()

        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 3))
        for title in ["图片", "报销", "退款", "AA 分摊", "保存为模板", "复制记账", "编辑", "删除"] {
            XCTAssertTrue(app.buttons[title].exists, "Missing inline action: \(title)")
        }
        XCTAssertTrue(app.staticTexts["币种"].exists)
        XCTAssertTrue(app.buttons["备注"].exists)
        XCTAssertFalse(app.buttons["更多交易操作"].exists)
    }

    func testTransactionNoteEditorFocusesKeyboard() {
        app.buttons["root-tab-ledger"].tap()
        let diningTransaction = app.descendants(matching: .any)["sample-transaction-dining"].firstMatch
        XCTAssertTrue(diningTransaction.waitForExistence(timeout: 3))
        diningTransaction.tap()

        let noteButton = app.buttons["备注"]
        XCTAssertTrue(noteButton.waitForExistence(timeout: 3))
        noteButton.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let editor = app.textViews["备注"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 3))
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

    private func waitForDataReady() {
        let ready = app.descendants(matching: .any)["app-data-ready"].firstMatch
        let failed = app.descendants(matching: .any)["app-data-seed-failed"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 12), "Sample data did not finish seeding")
        XCTAssertFalse(failed.exists, "Sample data seeding failed")
    }
}
