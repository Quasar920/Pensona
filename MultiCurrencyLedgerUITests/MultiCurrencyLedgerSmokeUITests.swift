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
        assertTab("statistics", marker: app.navigationBars["报表"])
    }

    func testBottomNavigationCentersEntryAndPlacesTapLogAboveRight() {
        let ledger = app.buttons["root-tab-ledger"]
        let assets = app.buttons["root-tab-assets"]
        let entry = app.buttons["root-entry-button"]
        let savings = app.buttons["root-tab-savings"]
        let statistics = app.buttons["root-tab-statistics"]
        let tapLog = app.buttons["taplog-button"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 3))
        XCTAssertTrue(tapLog.exists)

        XCTAssertLessThan(ledger.frame.midX, assets.frame.midX)
        XCTAssertLessThan(assets.frame.midX, entry.frame.midX)
        XCTAssertLessThan(entry.frame.midX, savings.frame.midX)
        XCTAssertLessThan(savings.frame.midX, statistics.frame.midX)
        XCTAssertGreaterThan(entry.frame.midY, app.frame.height * 0.75)
        XCTAssertEqual(entry.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(ledger.frame.midY, entry.frame.midY, accuracy: 2)
        XCTAssertLessThan(tapLog.frame.minY, entry.frame.minY)
        XCTAssertGreaterThan(tapLog.frame.midX, app.frame.midX)

        let initialTabCenters = [ledger, assets, savings, statistics].map { $0.frame.midX }
        statistics.tap()
        XCTAssertTrue(app.navigationBars["报表"].waitForExistence(timeout: 3))

        let finalTabCenters = [ledger, assets, savings, statistics].map { $0.frame.midX }
        for (initial, final) in zip(initialTabCenters, finalTabCenters) {
            XCTAssertEqual(initial, final, accuracy: 1)
        }
    }

    func testBookSwitcherUsesTapLogStyleMenu() {
        let switcher = app.buttons["home-book-switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 3))
        switcher.tap()

        let travelBook = app.buttons["旅行账本"]
        XCTAssertTrue(travelBook.waitForExistence(timeout: 3))
        travelBook.tap()
        XCTAssertTrue(switcher.label.contains("旅行账本"))
    }

    func testEntryCategorySublayerAndActionPanel() {
        openEntry()

        let dining = app.buttons["餐饮"].firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 3))
        dining.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["修改"].waitForExistence(timeout: 2))
        app.buttons["取消"].tap()

        dining.tap()
        XCTAssertTrue(app.buttons["新分类"].waitForExistence(timeout: 2))
        let subcategoryCard = app.descendants(matching: .any)["entry-subcategory-layer"]
        XCTAssertTrue(subcategoryCard.waitForExistence(timeout: 2))
        XCTAssertEqual(subcategoryCard.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertEqual(subcategoryCard.frame.midY, app.frame.midY, accuracy: 3)
        XCTAssertLessThan(subcategoryCard.frame.height, app.frame.height * 0.5)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.10)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["entry-subcategory-layer"].waitForNonExistence(timeout: 2))
    }

    func testEntryCloseImmediatelyDiscardsUnsavedAmount() {
        openEntry()
        scrollTo(app.buttons["1"].firstMatch)
        app.buttons["1"].firstMatch.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()

        XCTAssertTrue(app.buttons["root-entry-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["放弃这笔未保存的记账？"].exists)
    }

    func testEntryDateAndTimeUseSharedAnchoredWheelPicker() {
        openEntry()

        let dateTimeButton = app.buttons["entry-date-time-button"]
        XCTAssertTrue(dateTimeButton.waitForExistence(timeout: 2))
        dateTimeButton.tap()

        let wheel = app.descendants(matching: .any)["entry-date-time-wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 2))
        XCTAssertTrue(app.pickerWheels.firstMatch.exists)
        let nowButton = app.buttons["entry-date-time-now"]
        XCTAssertTrue(nowButton.exists)
        nowButton.tap()
        XCTAssertTrue(wheel.exists)
        XCTAssertTrue(dateTimeButton.exists)
        XCTAssertFalse(app.navigationBars["选择日期和时间"].exists)
        app.buttons["取消"].tap()
    }

    func testEntryContextGeniePanelsOpenAndClose() {
        openEntry()

        for (tag, title) in [
            ("AA", "AA 分摊"),
            ("组合支付", "组合支付"),
            ("优惠", "优惠")
        ] {
            let tagButton = app.buttons[tag].firstMatch
            scrollTo(tagButton)
            tagButton.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))

            let cancelButton = app.buttons["取消"].firstMatch
            let confirmButton = app.buttons["确认"].firstMatch
            XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
            XCTAssertTrue(confirmButton.exists)
            if tag == "组合支付" {
                let amountInput = app.buttons["entry-context-split-amount-0"]
                XCTAssertTrue(amountInput.waitForExistence(timeout: 2))
                amountInput.tap()
                XCTAssertTrue(app.otherElements["entry-context-input-caret"].exists)
            }
            cancelButton.tap()
            XCTAssertTrue(cancelButton.waitForNonExistence(timeout: 2))
        }
    }

    func testEntryContextPanelCancelsWithoutApplying() {
        openEntry()
        let aa = app.buttons["entry-context-tag-aa"]
        scrollTo(aa)
        aa.tap()
        XCTAssertTrue(app.staticTexts["AA 分摊"].waitForExistence(timeout: 2))
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["AA 分摊"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(aa.label.contains("不参与 AA"))
    }

    func testEntryKindSelectorSwitchesBetweenAllTransactionKinds() {
        openEntry()

        for kind in ["income", "transfer", "exchange", "expense"] {
            let selector = app.buttons["receipt-kind-\(kind)"]
            XCTAssertTrue(selector.waitForExistence(timeout: 2))
            selector.tap()
            XCTAssertTrue(selector.isSelected, "\(kind) should become the active transaction kind")
        }
    }

    func testDiscountContextAcceptsReceiptKeypadInput() {
        openEntry()

        let discount = app.buttons["entry-context-tag-discount"]
        scrollTo(discount)
        discount.tap()

        let panel = app.descendants(matching: .any)["entry-context-panel-discount"]
        XCTAssertTrue(panel.waitForExistence(timeout: 2))

        let keypad = app.descendants(matching: .any)["receipt-keypad"]
        let key = keypad.buttons["2"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 2))
        key.tap()
        XCTAssertTrue(panel.staticTexts["2"].waitForExistence(timeout: 2))

        app.buttons["确认"].firstMatch.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue(discount.label.contains("2"))
    }

    func testIncomeFeeTemplateAppliesImmediately() {
        openEntry()

        app.buttons["收入"].firstMatch.tap()
        scrollTo(app.buttons["1"].firstMatch)
        app.buttons["1"].firstMatch.tap()
        for _ in 0..<3 { app.buttons["0"].firstMatch.tap() }

        let feeTag = app.buttons["entry-context-tag-fee"]
        scrollTo(feeTag)
        feeTag.tap()

        let panel = app.descendants(matching: .any)["entry-context-panel-fee"]
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        XCTAssertEqual(panel.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertTrue(app.buttons["取消"].firstMatch.exists)
        XCTAssertTrue(app.buttons["完成"].firstMatch.exists)

        let template = app.buttons["entry-fee-template-5F44B167-3506-4DE5-A540-CF1496239E46"]
        XCTAssertTrue(template.waitForExistence(timeout: 2))
        template.tap()

        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(feeTag.waitForExistence(timeout: 2))
        XCTAssertTrue(feeTag.label.contains("3.80"), "Expected calculated fee in tag, got: \(feeTag.label)")
        XCTAssertTrue(app.staticTexts["996.2"].exists || app.staticTexts["996.20"].exists)
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

    func testSettingsPreviewShowsGroupedRowsAndAboutDetails() {
        app.terminate()
        app.launchEnvironment["APP_PREVIEW_SCREEN"] = "settings"
        app.launch()
        waitForDataReady()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["数据导入与导出"].exists)
        XCTAssertTrue(app.staticTexts["从表格或文件导入历史账单"].exists)

        app.staticTexts["显示、触觉与金额颜色"].tap()
        XCTAssertTrue(app.navigationBars["外观与金额颜色"].waitForExistence(timeout: 3))
        app.navigationBars["外观与金额颜色"].buttons.firstMatch.tap()

        for _ in 0..<4 { app.swipeUp() }
        let aboutFooter = app.buttons["settings-about-footer"]
        XCTAssertTrue(aboutFooter.waitForExistence(timeout: 3))
        aboutFooter.tap()
        XCTAssertTrue(app.navigationBars["关于与帮助"].waitForExistence(timeout: 3))
    }

    func testReceiptEntrySheetStructureAndKeypad() {
        openEntry()

        let sheet = app.descendants(matching: .any)["receipt-entry-sheet"].firstMatch
        let paper = app.descendants(matching: .any)["receipt-entry-paper"].firstMatch
        let handle = app.buttons["拖拽关闭记账"]
        XCTAssertTrue(paper.waitForExistence(timeout: 2))
        XCTAssertTrue(handle.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(sheet.frame.height, app.frame.height * 0.92)
        XCTAssertLessThan(sheet.frame.height, app.frame.height * 0.97)
        XCTAssertGreaterThanOrEqual(sheet.frame.minY, 38)
        XCTAssertLessThanOrEqual(sheet.frame.minY, 45)

        for identifier in ["expense", "income", "transfer", "exchange"] {
            XCTAssertTrue(app.buttons["receipt-kind-\(identifier)"].exists)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "receipt-account-row").count, 1)

        let firstRow = ["餐饮", "咖啡", "外卖", "购物", "交通"].map {
            app.buttons[$0].firstMatch
        }
        firstRow.forEach { XCTAssertTrue($0.exists) }
        for pair in zip(firstRow, firstRow.dropFirst()) {
            XCTAssertEqual(pair.0.frame.midY, pair.1.frame.midY, accuracy: 2)
            XCTAssertLessThan(pair.0.frame.midX, pair.1.frame.midX)
        }
        app.buttons["外卖"].firstMatch.tap()
        XCTAssertTrue(app.buttons["外卖"].firstMatch.isSelected)

        let topShot = XCTAttachment(screenshot: app.screenshot())
        topShot.name = "receipt-top"
        topShot.lifetime = .keepAlways
        add(topShot)

        let complete = app.buttons["完成"].firstMatch
        XCTAssertTrue(complete.isHittable, "The complete action must fit in the expanded Sheet without scrolling")
        for key in ["7", "8", "9", "加", "4", "5", "6", "减", "1", "2", "3", "乘", "0", ".", "除"] {
            XCTAssertTrue(app.buttons[key].firstMatch.exists, "Missing keypad key: \(key)")
        }
        XCTAssertTrue(app.buttons["下一笔"].exists)
        XCTAssertTrue(complete.exists)

        let bottomShot = XCTAttachment(screenshot: app.screenshot())
        bottomShot.name = "receipt-bottom"
        bottomShot.lifetime = .keepAlways
        add(bottomShot)
    }

    private func openEntry() {
        app.buttons["root-entry-button"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["receipt-entry-sheet"].firstMatch.waitForExistence(timeout: 3)
        )
    }

    private func scrollTo(_ element: XCUIElement, attempts: Int = 5) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertTrue(element.isHittable)
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
