import XCTest

final class PaymentSmokeUITests: XCTestCase {
    func testNormalUserJourneyCompletesIsolatedRide() {
        let app = XCUIApplication()
        app.launch()
        let whereTo = app.buttons["Where are you going?"]
        XCTAssertTrue(whereTo.waitForExistence(timeout: 20), app.debugDescription)
        whereTo.tap()
        let destination = app.textFields["Where to?"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), app.debugDescription)
        destination.tap()
        destination.typeText("1100 E Division St, Lombard, IL")
        app.buttons["Continue"].tap()
        let chooseSaver = app.buttons["Choose Saver"]
        XCTAssertTrue(chooseSaver.waitForExistence(timeout: 30), app.debugDescription)
        chooseSaver.tap()
        let testPayment = app.buttons.containing(.staticText, identifier: "Test payment").firstMatch
        XCTAssertTrue(testPayment.waitForExistence(timeout: 20), app.debugDescription)
        testPayment.tap()
        app.buttons["Confirm ride"].tap()
        XCTAssertTrue(app.staticTexts["Finding your ride"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Test ride complete"].waitForExistence(timeout: 180), app.debugDescription)
        XCTAssertTrue(app.staticTexts["$0.00"].exists, app.debugDescription)
    }

    func testConfirmIsolatedTestRide() {
        let app = XCUIApplication()
        app.launchArguments.append("--jiylo-payment-smoke")
        app.launch()

        let testPayment = app.buttons.containing(.staticText, identifier: "Test payment").firstMatch
        XCTAssertTrue(testPayment.waitForExistence(timeout: 30), app.debugDescription)
        testPayment.tap()

        let confirm = app.buttons["Confirm ride"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Finding your ride"].waitForExistence(timeout: 30), app.debugDescription)
    }

    func testCompletedIsolatedTestRideShowsReceipt() {
        let app = XCUIApplication()
        app.launchArguments.append("--jiylo-payment-smoke")
        app.launch()

        let testPayment = app.buttons.containing(.staticText, identifier: "Test payment").firstMatch
        XCTAssertTrue(testPayment.waitForExistence(timeout: 30), app.debugDescription)
        testPayment.tap()

        let confirm = app.buttons["Confirm ride"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Finding your ride"].waitForExistence(timeout: 30), app.debugDescription)

        // The local test driver is advanced by the isolated backend fixture
        // while this physical-device UI remains open.
        XCTAssertTrue(app.staticTexts["Test ride complete"].waitForExistence(timeout: 180), app.debugDescription)
        XCTAssertTrue(app.staticTexts["$0.00"].exists)
    }
}
