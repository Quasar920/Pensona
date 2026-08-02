import XCTest

final class MultiCurrencyLedgerPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["HOME_SAMPLE_DATA"] = "1"
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["APP_PREVIEW_LANGUAGE"] = "zh-Hans"
        if let profilerWindow = ProcessInfo.processInfo.environment["UI_PROFILER_ATTACH_SECONDS"] {
            app.launchEnvironment["UI_PROFILER_ATTACH_SECONDS"] = profilerWindow
        }
        switch app.state {
        case .runningBackground, .runningBackgroundSuspended, .runningForeground:
            app.activate()
        default:
            app.launch()
        }
        XCUIDevice.shared.orientation = .portrait
        let ready = app.descendants(matching: .any)["app-data-ready"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 12), "Sample data did not finish seeding")
        XCTAssertFalse(app.descendants(matching: .any)["app-data-seed-failed"].exists)
        XCTAssertTrue(app.buttons["root-tab-ledger"].waitForExistence(timeout: 8))
    }

    func testTimeProfilerJourney() {
        waitForExternalProfilerAttachment()

        exerciseMonthSwitches(iterations: 3)
        exerciseEntryExpansion(iterations: 3)
        exerciseAccountDetail(iterations: 3)
        exerciseStatisticsRanges(iterations: 3)
    }

    func testAnimationHitchesJourney() {
        waitForExternalProfilerAttachment()

        for identifier in ["ledger", "assets", "savings", "statistics"] {
            app.buttons["root-tab-\(identifier)"].tap()
            for _ in 0..<8 {
                app.swipeUp(velocity: .fast)
                app.swipeDown(velocity: .fast)
            }
        }
    }

    func testAllocationsJourney() {
        waitForExternalProfilerAttachment()

        app.buttons["root-entry-button"].tap()
        XCTAssertTrue(app.navigationBars["记账"].waitForExistence(timeout: 5))

        let pager = app.descendants(matching: .any)["entry-category-pager"].firstMatch
        if pager.waitForExistence(timeout: 3) {
            for _ in 0..<12 {
                pager.swipeLeft(velocity: .fast)
                pager.swipeRight(velocity: .fast)
            }
        }

        let dining = app.buttons["餐饮"].firstMatch
        if dining.waitForExistence(timeout: 3) {
            for _ in 0..<4 {
                dining.press(forDuration: 1.1)
                if app.buttons["修改"].waitForExistence(timeout: 2) {
                    app.buttons["修改"].tap()
                    app.swipeUp(velocity: .fast)
                    app.swipeDown(velocity: .fast)
                    app.buttons["取消"].firstMatch.tap()
                }
            }
        }

        for _ in 0..<20 {
            app.buttons["1"].firstMatch.tap()
            app.buttons["2"].firstMatch.tap()
            app.buttons["3"].firstMatch.tap()
            let delete = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "删除")).firstMatch
            if delete.exists { delete.tap() }
        }
        app.buttons["关闭"].tap()
    }

    func testSwiftUIUpdatesJourney() {
        waitForExternalProfilerAttachment()

        for _ in 0..<16 {
            app.buttons["root-tab-ledger"].tap()
            app.buttons["bill-month-previous"].tap()
            app.buttons["bill-month-next"].tap()
            app.buttons["root-tab-assets"].tap()
            app.buttons["root-tab-savings"].tap()
            app.buttons["root-tab-statistics"].tap()
            if app.buttons["周"].exists { app.buttons["周"].tap() }
            if app.buttons["月"].exists { app.buttons["月"].tap() }
        }
    }

    private func waitForExternalProfilerAttachment() {
        let configuredSeconds = ProcessInfo.processInfo.environment["UI_PROFILER_ATTACH_SECONDS"]
            .flatMap(TimeInterval.init) ?? 0
        guard configuredSeconds > 0 else { return }
        let attachmentWindow = XCTWaiter.wait(
            for: [XCTestExpectation(description: "External profiler attachment window")],
            timeout: configuredSeconds
        )
        XCTAssertEqual(attachmentWindow, .timedOut)
    }

    private func exerciseMonthSwitches(iterations: Int) {
        app.buttons["root-tab-ledger"].tap()
        XCTAssertTrue(app.buttons["bill-month-previous"].waitForExistence(timeout: 4))
        for _ in 0..<iterations {
            app.buttons["bill-month-previous"].tap()
            app.buttons["bill-month-next"].tap()
        }
    }

    private func exerciseEntryExpansion(iterations: Int) {
        for _ in 0..<iterations {
            let entryButton = app.buttons["root-entry-button"].firstMatch
            XCTAssertTrue(entryButton.waitForExistence(timeout: 8))
            entryButton.tap()

            let entryNavigationBar = app.navigationBars["记账"].firstMatch
            XCTAssertTrue(entryNavigationBar.waitForExistence(timeout: 12))
            let closeButton = entryNavigationBar.buttons["entry-close-button"].firstMatch
            XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
            XCTAssertTrue(waitForHittable(closeButton, timeout: 10))
            closeButton.tap()

            if entryNavigationBar.waitForNonExistence(timeout: 5) == false {
                let retryCloseButton = entryNavigationBar.buttons["entry-close-button"].firstMatch
                if retryCloseButton.exists, retryCloseButton.isHittable {
                    retryCloseButton.tap()
                }
            }
            XCTAssertTrue(entryNavigationBar.waitForNonExistence(timeout: 20))
            XCTAssertTrue(app.buttons["root-entry-button"].firstMatch.waitForExistence(timeout: 20))
        }
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func exerciseAccountDetail(iterations: Int) {
        app.buttons["root-tab-assets"].tap()
        let account = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "asset-account-")
        ).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))

        for _ in 0..<iterations {
            account.tap()
            XCTAssertTrue(app.descendants(matching: .any)["account-detail-screen"].waitForExistence(timeout: 3))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(account.waitForExistence(timeout: 3))
        }
    }

    private func exerciseStatisticsRanges(iterations: Int) {
        app.buttons["root-tab-statistics"].tap()
        XCTAssertTrue(app.navigationBars["统计"].waitForExistence(timeout: 5))
        for _ in 0..<iterations {
            for title in ["周", "月", "年"] where app.buttons[title].exists {
                app.buttons[title].tap()
                app.buttons["statistics-range-previous"].tap()
                app.buttons["statistics-range-next"].tap()
            }
        }
    }
}
