import XCTest
import StoreKitTest
import StoreKit

@MainActor final class SupportUITests: XCTestCase {
    private func session(empty: Bool = false) throws -> SKTestSession {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MonoViewSupport", withExtension: "storekit"))
        let session: SKTestSession
        if empty {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            json["products"] = []
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("EmptySupport-\(UUID()).storekit")
            try JSONSerialization.data(withJSONObject: json).write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            session = try SKTestSession(contentsOf: temporary)
        } else {
            session = try SKTestSession(contentsOf: file)
        }
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        return session
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.isHittable && element.frame.minY > 150 && element.frame.maxY < app.windows.firstMatch.frame.maxY - 140 { return }
            let up = element.frame.minY >= 150
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.8)))
        }
        XCTFail("Control is not fully visible: \(element)")
    }
    private func openSupport(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-guideVersion", "1"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        let settings = app.buttons["settings"]
        if !settings.isHittable { app.scrollViews.firstMatch.swipeUp() }
        settings.tap()
        let support = app.buttons["openSupport"]
        reveal(support, in: app); support.tap()
        XCTAssertTrue(app.buttons["supportDone"].waitForExistence(timeout: 5))
    }

    func testOptionalSupportCanBeRepeatedAndClosedWithoutChangingAppAccess() throws {
        continueAfterFailure = false
        let session = try session()
        let app = XCUIApplication()
        openSupport(app)
        let small = app.buttons["support-com.monoview.support.small"]
        XCTAssertTrue(small.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Support MonoView"; shot.lifetime = .keepAlways; add(shot)
        reveal(small, in: app); small.tap()
        let thanks = app.descendants(matching: .any).matching(identifier: "supportThanks").firstMatch
        XCTAssertTrue(thanks.waitForExistence(timeout: 10))
        reveal(small, in: app); small.tap()
        XCTAssertTrue(thanks.waitForExistence(timeout: 10))
        XCTAssertEqual(session.allTransactions().count, 2)
        app.buttons["supportDone"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chooseImage"].isEnabled)
    }

    func testUnavailableProductsStillAllowLeavingAndUsingApp() throws {
        continueAfterFailure = false
        let session = try session(empty: true)
        let app = XCUIApplication()
        openSupport(app)
        XCTAssertTrue(app.staticTexts["supportUnavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["support-com.monoview.support.small"].exists)
        app.buttons["supportDone"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["chooseImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testLargestTextKeepsOptionalSupportDismissible() throws {
        continueAfterFailure = false
        let session = try session()
        let app = XCUIApplication()
        openSupport(app, largeText: true)
        XCTAssertTrue(app.buttons["supportDone"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Support largest text"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["supportDone"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(session.allTransactions().isEmpty)
    }
    func testFailedSupportCanBeRetried() async throws {
        continueAfterFailure = false
        let session = try session()
        let app = XCUIApplication()
        openSupport(app)
        let small = app.buttons["support-com.monoview.support.small"]
        XCTAssertTrue(small.waitForExistence(timeout: 10))
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        reveal(small, in: app); small.tap()
        XCTAssertTrue(app.staticTexts["supportNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["supportThanks"].exists)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        reveal(small, in: app); small.tap()
        XCTAssertTrue(app.staticTexts["supportThanks"].waitForExistence(timeout: 10))
    }

    func testPendingSupportThanksOnlyAfterApproval() throws {
        continueAfterFailure = false
        let session = try session()
        session.askToBuyEnabled = true
        let app = XCUIApplication()
        openSupport(app)
        let small = app.buttons["support-com.monoview.support.small"]
        XCTAssertTrue(small.waitForExistence(timeout: 10))
        reveal(small, in: app); small.tap()
        XCTAssertTrue(app.staticTexts["supportNotice"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["supportThanks"].exists)
        XCTAssertFalse(small.isEnabled)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.staticTexts["supportThanks"].waitForExistence(timeout: 10))
        XCTAssertTrue(small.isEnabled)
    }

}
