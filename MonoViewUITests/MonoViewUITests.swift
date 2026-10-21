import XCTest

final class MonoViewUITests: XCTestCase {
    @MainActor
    func testSweepsCanBeReviewedWithoutForcingAHandGuess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 10))
        app.buttons["Start sweeps"].tap()
        for y in [0.58, 0.66] {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: y - 0.16))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let review = app.buttons["Review"]
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.staticTexts["Confirm your hand"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use manual setup"].exists)
    }

    @MainActor
    func testReachSetupAndReopening() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["Use manual setup"].waitForExistence(timeout: 10))
        app.buttons["Use manual setup"].tap()
        XCTAssertTrue(app.buttons["reachNext"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Left hand"].tap()
        app.buttons["reachNext"].tap()
        app.segmentedControls.buttons["Wide"].tap()
        app.segmentedControls.buttons["Middle"].tap()
        app.buttons["reachTrial0"].tap()
        app.buttons["reachTrial8"].tap()
        XCTAssertEqual(app.buttons["reachTrial0"].value as? String, "Tried")
        app.buttons["reachNext"].tap()
        app.buttons["reachTrial4"].tap()
        app.buttons["reachNext"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        let reopen = app.buttons["reopenReachSetup"]
        if !reopen.isHittable { app.swipeUp() }
        reopen.tap()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsCanBeCompletedWithoutSwipeDismiss() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "2"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Make it yours"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Left"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        app.segmentedControls.buttons["Right"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
    }
}
