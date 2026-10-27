import XCTest

final class MonoViewUITests: XCTestCase {
    @MainActor
    func testReaderSpeechCanPauseResumeAndStopOnExit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["photoTools"].waitForExistence(timeout: 10)); app.buttons["photoTools"].tap()
        app.buttons["readPhotoText"].tap()
        XCTAssertTrue(app.staticTexts["recognizedText"].waitForExistence(timeout: 40))
        let speak = app.buttons["readerSpeak"]
        speak.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        speak.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        speak.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["readerBack"].tap()
        XCTAssertTrue(app.buttons["readPhotoText"].waitForExistence(timeout: 5))
        app.buttons["readPhotoText"].tap()
        XCTAssertTrue(app.buttons["Read aloud"].waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["readerStop"].isEnabled)
        app.buttons["readerBack"].tap(); app.buttons["photoToolsDone"].tap()
    }

    @MainActor
    func testReaderNoTextCanRetryCompareAndLeave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "--ui-test-blank-photo", "-guideVersion", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["photoTools"].waitForExistence(timeout: 10)); app.buttons["photoTools"].tap()
        app.buttons["readPhotoText"].tap()
        XCTAssertTrue(app.staticTexts["readerEmpty"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["readerRetry"].isEnabled)
        app.buttons["readerRetry"].tap()
        XCTAssertTrue(app.staticTexts["readerEmpty"].waitForExistence(timeout: 40))
        app.buttons["readerCompare"].tap()
        XCTAssertTrue(app.images["readerOriginalPhoto"].exists)
        app.buttons["readerBack"].tap(); app.buttons["photoToolsDone"].tap()
    }

    @MainActor
    func testReaderRecognizesPhotoComparesAndReturnsToViewer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1"]
        app.launch()
        let read = app.buttons["readText"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        XCTAssertTrue(read.isHittable)
        let panel = XCTAttachment(screenshot: app.screenshot()); panel.name = "Direct Read text button"; panel.lifetime = .keepAlways; add(panel)
        read.tap()
        let text = app.staticTexts["recognizedText"]
        XCTAssertTrue(text.waitForExistence(timeout: 40))
        XCTAssertTrue(text.label.lowercased().contains("a clearer view"))
        XCTAssertTrue(app.buttons["readerSpeak"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Recognized text reader"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["readerCompare"].tap()
        XCTAssertTrue(app.images["readerOriginalPhoto"].exists)
        app.buttons["readerCompare"].tap()
        XCTAssertTrue(text.exists)
        app.buttons["readerOptions"].tap()
        XCTAssertTrue(app.buttons["readerOptionsDone"].waitForExistence(timeout: 5))
        app.buttons["Cream"].tap()
        app.buttons["readerOptionsDone"].tap()
        app.buttons["readerBack"].tap()
        XCTAssertTrue(app.buttons["readText"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["readerBack"].exists)
    }

    @MainActor
    func testReaderWithLargestTextCanCompareAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let read = app.buttons["readText"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        for _ in 0..<6 { if read.isHittable { break }; app.swipeUp() }
        read.tap()
        XCTAssertTrue(app.staticTexts["recognizedText"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["readerBack"].isHittable)
        app.buttons["readerCompare"].tap()
        XCTAssertTrue(app.images["readerOriginalPhoto"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Reader largest text controls"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["readerBack"].tap()
        XCTAssertTrue(app.buttons["readText"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhotoToolsWithLargestTextCanCloseWithoutSwipeDismiss() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let tools = app.buttons["photoTools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10)); tools.tap()
        XCTAssertTrue(app.buttons["photoToolsDone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["photoToolsDone"].isHittable)
        app.buttons["photoToolsDone"].tap()
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhotoFiltersRulerPersistenceAndReset() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "YES"]
        app.launch()
        let tools = app.buttons["photoTools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10)); tools.tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 {
                if element.isHittable && element.frame.minY > 140 && element.frame.maxY < app.windows.firstMatch.frame.maxY - 130 { break }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: element.frame.minY < 140 ? 0.85 : 0.4))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(element.isHittable)
        }
        func toggle(_ id: String) {
            let element = app.switches[id]; reveal(element)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let reset = app.buttons["resetPhotoTools"]
        reveal(reset); reset.tap()
        toggle("photoGrayscale"); XCTAssertEqual(app.switches["photoGrayscale"].value as? String, "1")
        toggle("photoInverted"); XCTAssertEqual(app.switches["photoInverted"].value as? String, "1")
        toggle("showOriginal")
        XCTAssertFalse(app.switches["photoGrayscale"].isEnabled)
        toggle("showOriginal")
        toggle("readingRulerToggle")
        XCTAssertTrue(app.sliders["readingRulerPosition"].exists)
        let previewShot = XCTAttachment(screenshot: app.screenshot()); previewShot.name = "Photo tools live preview"; previewShot.lifetime = .keepAlways; add(previewShot)
        app.buttons["photoToolsDone"].tap()
        let grip = app.descendants(matching: .any).matching(identifier: "readingRulerHandle").firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        let before = grip.frame
        grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        XCTAssertLessThan(grip.frame.minY, before.minY)
        let position = grip.value as? String
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Filters and reading ruler"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(grip.waitForExistence(timeout: 10)); XCTAssertEqual(grip.value as? String, position)
        tools.tap()
        XCTAssertEqual(app.switches["photoGrayscale"].value as? String, "1")
        XCTAssertEqual(app.switches["photoInverted"].value as? String, "1")
        reveal(reset); reset.tap()
        app.buttons["photoToolsDone"].tap()
        XCTAssertFalse(grip.exists)
    }

    @MainActor
    func testComfortSettingsPersistLockAndReset() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "YES"]
        app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<16 {
                let box = element.frame
                if element.isHittable && box.minY > 160 && box.maxY < app.windows.firstMatch.frame.maxY - 160 { return }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: box.minY < 160 ? 0.75 : 0.45))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTFail("Setting did not become fully visible: \(element)")
        }
        app.buttons["settings"].tap()
        let comfort = app.descendants(matching: .any).matching(identifier: "comfortSettings").firstMatch
        reveal(comfort); comfort.tap()
        let reset = app.buttons["resetComfort"]
        reveal(reset); reset.tap()
        let bigger = app.switches["largerControls"]
        reveal(bigger); bigger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(bigger.value as? String, "1")
        let labels = app.switches["showControlLabels"]
        reveal(labels); labels.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(labels.value as? String, "1")
        let lock = app.switches["lockControls"]
        reveal(lock); lock.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(lock.value as? String, "1")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Comfort settings preview"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        let handle = app.descendants(matching: .any).matching(identifier: "panelHandle").firstMatch
        let before = handle.frame
        let menuShot = XCTAttachment(screenshot: app.screenshot()); menuShot.name = "Large controls with labels"; menuShot.lifetime = .keepAlways; add(menuShot)
        XCTAssertTrue(app.buttons["settings"].isHittable)
        XCTAssertTrue(app.buttons["chooseImage"].isHittable)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        XCTAssertEqual(handle.frame.minY, before.minY, accuracy: 2)
        app.terminate(); app.launch()
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCTAssertTrue((handle.value as? String ?? "").contains("Position locked"))
        app.buttons["settings"].tap()
        reveal(comfort); comfort.tap()
        reveal(reset); reset.tap()
        app.buttons["Done"].tap()
        XCTAssertFalse((handle.value as? String ?? "").contains("Position locked"))
    }

    @MainActor
    func testTiltDotLongPressMovesWithoutStoppingAndPositionPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "YES", "-preferredHand", "right"]
        app.launch()
        XCTAssertTrue(app.buttons["startTilt"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["resetPanelPosition"].tap()
        app.buttons["Done"].tap()
        let panelShot = XCTAttachment(screenshot: app.screenshot()); panelShot.name = "Compact panel"; panelShot.lifetime = .keepAlways; add(panelShot)
        app.buttons["startTilt"].tap()
        let dot = app.buttons["stopTiltDot"]
        XCTAssertTrue(dot.waitForExistence(timeout: 5))
        let before = dot.frame
        dot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        XCTAssertTrue(dot.exists)
        XCTAssertFalse(app.buttons["settings"].exists)
        XCTAssertLessThan(dot.frame.minY, before.minY)
        XCTAssertGreaterThanOrEqual(dot.frame.minY, app.windows.firstMatch.frame.height * 0.4)
        XCTAssertGreaterThanOrEqual(dot.frame.minX, 0)
        XCTAssertLessThanOrEqual(dot.frame.maxX, app.windows.firstMatch.frame.maxX)
        let moved = dot.frame
        let dotShot = XCTAttachment(screenshot: app.screenshot()); dotShot.name = "Moved accessibility dot"; dotShot.lifetime = .keepAlways; add(dotShot)
        dot.tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
        app.buttons["startTilt"].tap()
        XCTAssertTrue(dot.waitForExistence(timeout: 5))
        XCTAssertEqual(dot.frame.minX, moved.minX, accuracy: 2)
        XCTAssertEqual(dot.frame.minY, moved.minY, accuracy: 2)
        dot.tap()
    }

    @MainActor
    func testTiltDoubleTapAndThumbSweepsKeepDotAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "YES"]
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
            app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "YES",
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
    func testGuideSelectsHandPracticesAndDoesNotRepeat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-guideVersion", "0"]
        app.launch()
        let next = app.buttons["guideNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["guideListen"].exists)
        for name in ["Welcome"] {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        next.tap()
        let hands = XCTAttachment(screenshot: app.screenshot()); hands.name = "Choose hand"; hands.lifetime = .keepAlways; add(hands)
        XCTAssertFalse(next.isEnabled)
        XCTAssertGreaterThan(app.buttons["guideListen"].frame.minY, app.buttons["guideBack"].frame.maxY)
        XCTAssertLessThan(app.staticTexts["Choose the hand you use to hold your phone."].frame.maxY, app.buttons["guideHand-left"].frame.minY)
        app.buttons["guideHand-left"].tap()
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "panelHandle").firstMatch.exists)
        XCTAssertGreaterThan(app.buttons["guideListen"].frame.minY, app.buttons["guideBack"].frame.maxY)
        XCTAssertGreaterThan(app.descendants(matching: .any).matching(identifier: "panelHandle").firstMatch.frame.minY, app.windows.firstMatch.frame.height * 0.5)
        let practice = XCTAttachment(screenshot: app.screenshot()); practice.name = "Position panel"; practice.lifetime = .keepAlways; add(practice)
        let comfortChoice = app.buttons["See controls comfortably?"]
        comfortChoice.tap()
        XCTAssertTrue(app.switches["largerControls"].exists)
        app.switches["largerControls"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "Guide comfort preview"; preview.lifetime = .keepAlways; add(preview)
        app.switches["largerControls"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        comfortChoice.tap()
        XCTAssertTrue(app.buttons["Try zoom in"].waitForExistence(timeout: 5))
        app.buttons["Try zoom in"].tap()
        XCTAssertTrue(app.staticTexts["Button reached ✓"].exists)
        next.tap()
        let photo = XCTAttachment(screenshot: app.screenshot()); photo.name = "Open photo"; photo.lifetime = .keepAlways; add(photo)
        next.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["guideNext"].exists)
        app.buttons["settings"].tap()
        app.buttons["reopenGuide"].tap()
        XCTAssertTrue(app.buttons["guideNext"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGuideCanFinishWithLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-guideVersion", "0", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["guideNext"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.staticTexts["Welcome to MonoView"].frame.height, 80)
        func tapVisible(_ element: XCUIElement) {
            for _ in 0..<6 {
                if element.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable)
            element.tap()
        }
        tapVisible(app.buttons["guideNext"])
        tapVisible(app.buttons["guideHand-right"])
        tapVisible(app.buttons["guideNext"])
        tapVisible(app.buttons["guideNext"])
        tapVisible(app.buttons["guideFinish"])
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPanelDragStaysOnScreenAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-guideVersion", "1", "-preferredHand", "right"]
        app.launch()
        let handle = app.descendants(matching: .any).matching(identifier: "panelHandle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)))
        let moved = handle.frame
        XCTAssertGreaterThanOrEqual(moved.minX, 0)
        XCTAssertGreaterThanOrEqual(moved.minY, screen.height * 0.4)
        XCTAssertLessThanOrEqual(moved.maxX, screen.maxX)
        app.terminate()
        app.launch()
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCTAssertEqual(handle.frame.minX, moved.minX, accuracy: 2)
        XCTAssertEqual(handle.frame.minY, moved.minY, accuracy: 2)
    }

    @MainActor
    func testFirstTiltShowsVisualInstructions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-tilt", "-guideVersion", "1", "-tiltGuideSeen", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["startTilt"].waitForExistence(timeout: 10))
        app.buttons["startTilt"].tap()
        let next = app.buttons["tiltGuideNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["stopTiltDot"].waitForExistence(timeout: 5))
        app.buttons["stopTiltDot"].tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsCanBeCompletedWithoutSwipeDismiss() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-guideVersion", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Make it yours"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Left"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
    }
}
