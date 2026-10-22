import XCTest

final class MonoViewUITests: XCTestCase {
    @MainActor
    func testTiltDoubleTapAndThumbSweepsKeepDotAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-reachCalibrationVersion", "2", "-purposeIntroSeen", "YES"]
        app.launch()
        let tilt = app.buttons["startTilt"]
        XCTAssertTrue(tilt.waitForExistence(timeout: 10))
        tilt.tap()
        let dot = app.buttons["stopTiltDot"]
        XCTAssertTrue(dot.waitForExistence(timeout: 5))
        let photo = app.images["viewerImage"]
        func zoomPercent() -> Int? {
            Int((photo.value as? String ?? "").filter(\.isNumber))
        }
        photo.doubleTap()
        XCTAssertEqual(zoomPercent(), 2000)
        photo.doubleTap()
        XCTAssertEqual(zoomPercent(), 100)
        XCTAssertTrue(dot.exists)
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.72))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.48))
        bottom.press(forDuration: 0.1, thenDragTo: top)
        let zoomedValue = zoomPercent() ?? 0
        XCTAssertGreaterThan(zoomedValue, 100)
        XCTAssertTrue(dot.exists)
        top.press(forDuration: 0.1, thenDragTo: bottom)
        XCTAssertLessThan(zoomPercent() ?? 2000, zoomedValue)
        XCTAssertTrue(dot.exists)
        dot.tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTiltCollapsesToDotAndTapRestoresPanelForEitherHand() {
        continueAfterFailure = false
        for hand in ["left", "right"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-tilt", "-reachCalibrationVersion", "2", "-purposeIntroSeen", "YES",
                                   "-preferredHand", hand, "-controlLift", "0"]
            app.launch()
            let tilt = app.buttons["startTilt"]
            XCTAssertTrue(tilt.waitForExistence(timeout: 10))
            XCTAssertTrue(tilt.isEnabled)
            tilt.tap()
            let dot = app.buttons["stopTiltDot"]
            XCTAssertTrue(dot.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["settings"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Tilt dot - \(hand) hand"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertGreaterThanOrEqual(dot.frame.width, 60)
            XCTAssertGreaterThanOrEqual(dot.frame.height, 60)
            if hand == "left" { XCTAssertLessThan(dot.frame.midX, app.windows.firstMatch.frame.midX) }
            else { XCTAssertGreaterThan(dot.frame.midX, app.windows.firstMatch.frame.midX) }
            dot.tap()
            XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(tilt.isEnabled)
            XCTAssertFalse(dot.exists)
            app.terminate()
        }
    }

    @MainActor
    func testPurposeLeadsToSetupAndIsNotRepeated() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0", "-purposeIntroSeen", "NO"]
        app.launch()
        let next = app.buttons["purposeContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Made for people with low vision and for anyone who uses a phone with one hand."].exists)
        XCTAssertEqual(next.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.width, 250)
        XCTAssertGreaterThanOrEqual(next.frame.height, 56)
        next.tap()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-reachCalibrationVersion", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["purposeContinue"].exists)
    }

    @MainActor
    func testSweepsCanBeReviewedWithoutForcingAHandGuess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0", "-purposeIntroSeen", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 10))
        app.buttons["Start sweeps"].tap()
        let area = app.otherElements["thumbSweepArea"]
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        for y in [0.60, 0.76] {
            let start = area.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y))
            let end = area.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: y - 0.24))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let review = app.buttons["Review"]
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.staticTexts["Confirm your hand"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use manual setup"].exists)
    }

    @MainActor
    func testIntroductionIsCenteredForEitherSavedHand() {
        continueAfterFailure = false
        for hand in ["left", "right"] {
            let app = XCUIApplication()
            app.launchArguments = ["-reachCalibrationVersion", "0", "-preferredHand", hand, "-purposeIntroSeen", "YES"]
            app.launch()
            let start = app.buttons["Start sweeps"]
            let manual = app.buttons["Use manual setup"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            let screen = app.windows.firstMatch.frame
            for button in [start, manual] {
                XCTAssertTrue(button.isHittable)
                XCTAssertEqual(button.frame.midX, screen.midX, accuracy: 2)
                XCTAssertGreaterThan(button.frame.midY, screen.height * 0.4)
                XCTAssertLessThan(button.frame.maxY, screen.height * 0.85)
            }
            XCTAssertFalse(app.buttons["What is saved?"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testSweepsOutsideTheOutlineAreNotRecorded() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0", "-purposeIntroSeen", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Start sweeps"].waitForExistence(timeout: 10))
        app.buttons["Start sweeps"].tap()
        let area = app.otherElements["thumbSweepArea"]
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        // Both gestures stay in the header, above the recording field.
        for y in [0.12, 0.18] {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: y))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(app.staticTexts["0 sweeps recorded"].exists)
        XCTAssertFalse(app.buttons["Review"].isEnabled)
    }

    @MainActor
    func testReachSetupAndReopening() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reachCalibrationVersion", "0", "-purposeIntroSeen", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Use manual setup"].waitForExistence(timeout: 10))
        app.buttons["Use manual setup"].tap()
        XCTAssertTrue(app.buttons["reachNext"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Left hand"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].exists)
        app.buttons["reachNext"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 2"].exists)
        app.segmentedControls.buttons["Wide"].tap()
        app.segmentedControls.buttons["Middle"].tap()
        app.buttons["reachTrial0"].tap()
        app.buttons["reachTrial8"].tap()
        XCTAssertEqual(app.buttons["reachTrial0"].value as? String, "Tried")
        XCTAssertEqual(app.buttons["reachNext"].label, "Save setup")
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
        app.launchArguments = ["-reachCalibrationVersion", "2", "-purposeIntroSeen", "YES"]
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
