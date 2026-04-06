//
//  genchiUITests.swift
//  genchiUITests
//
//  Created by 咚咚锵 on 2026/4/1.
//

import XCTest

final class genchiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCorrectionToastDismissesAfterSubmission() throws {
        let app = makeLoggedInApp()
        app.launchEnvironment["UITEST_FORCE_CORRECTION_SUCCESS"] = "1"
        app.launchArguments += [
            "UITEST_AUTO_OPEN_CORRECTION",
            "UITEST_DISABLE_LOCATION_PROMPT"
        ]
        app.launch()

        let correctionSheetTitle = app.navigationBars["反馈问题"]
        XCTAssertTrue(correctionSheetTitle.waitForExistence(timeout: 15))

        app.buttons["店铺识别错误"].tap()

        let submitButton = app.buttons["提交反馈"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let doneButton = app.buttons["完成"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 15))
        doneButton.tap()

        let toast = app.staticTexts["反馈已提交"]
        XCTAssertTrue(toast.waitForExistence(timeout: 2))

        sleep(3)
        XCTAssertFalse(toast.exists)
    }

    @MainActor
    func testParseLinkSheetDefaultsToSingleOnlyOnFirstEntry() throws {
        let app = makeLoggedInApp()
        app.launchEnvironment["UITEST_CLEAR_PARSE_LAST_SCOPE"] = "1"
        app.launchArguments += [
            "UITEST_AUTO_OPEN_PARSE_LINK",
            "UITEST_DISABLE_LOCATION_PROMPT"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["从抖音添加"].waitForExistence(timeout: 15))

        let singleOption = app.buttons["parse-scope-single"]
        let followAllOption = app.buttons["parse-scope-follow-all"]
        XCTAssertTrue(singleOption.waitForExistence(timeout: 5))
        XCTAssertTrue(followAllOption.exists)
        XCTAssertEqual(singleOption.value as? String, "selected")
        XCTAssertEqual(followAllOption.value as? String, "unselected")
        XCTAssertFalse(app.staticTexts["parse-scope-single-badge"].exists)
        XCTAssertFalse(app.staticTexts["parse-scope-follow-all-badge"].exists)
    }

    @MainActor
    func testParseLinkSheetRestoresLastSelectedScope() throws {
        let app = makeLoggedInApp()
        app.launchEnvironment["UITEST_PARSE_LAST_SCOPE"] = "followAll"
        app.launchArguments += [
            "UITEST_AUTO_OPEN_PARSE_LINK",
            "UITEST_DISABLE_LOCATION_PROMPT"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["从抖音添加"].waitForExistence(timeout: 15))

        let singleOption = app.buttons["parse-scope-single"]
        let followAllOption = app.buttons["parse-scope-follow-all"]
        XCTAssertTrue(singleOption.waitForExistence(timeout: 5))
        XCTAssertTrue(followAllOption.exists)
        XCTAssertEqual(singleOption.value as? String, "unselected")
        XCTAssertEqual(followAllOption.value as? String, "selected")
        XCTAssertTrue(app.staticTexts["parse-scope-follow-all-badge"].exists)
        XCTAssertFalse(app.staticTexts["parse-scope-single-badge"].exists)

        singleOption.tap()
        XCTAssertEqual(singleOption.value as? String, "selected")
        XCTAssertEqual(followAllOption.value as? String, "unselected")
        XCTAssertTrue(app.staticTexts["parse-scope-follow-all-badge"].exists)
        XCTAssertFalse(app.staticTexts["parse-scope-single-badge"].exists)
    }

    @MainActor
    private func makeLoggedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_USER_ID"] = "e86b7277-a602-596c-b74c-fdde11878d9d"
        return app
    }
}
