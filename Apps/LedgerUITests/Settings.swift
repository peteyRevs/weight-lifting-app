import XCTest

/// F14 S1, criterion 1, on screen: Settings in the running app, on the seed program (`-LEDGER_UITEST_PROGRAM seed`,
/// F08) and at noon on Wednesday of its week 5 (`-LEDGER_UITEST_NOW`). Today's gear opens Settings; KG is chosen
/// there; back on Today, without a relaunch, the week's volume tile reads in kilograms. Nightly only: the `PR` plan
/// selects `Smoke`.
///
/// A fresh install in the simulator's region (en_US) starts in pounds (N3), which the test checks first. The
/// Library's PRs in kilograms need a finished workout, which a UI-test launch has none of; they are
/// `LibraryStoreTests.unitsChanged_redrawsThePRs`'.
final class Settings: XCTestCase {
    private static let sessionDay = "2026-09-16T12:00:00Z"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_kilograms_chosenInSettings_reachToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", Self.sessionDay]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(Self.element(saying: "lb moved", in: app).waitForExistence(timeout: 10))

        app.buttons["Settings"].tap()
        let title = app.staticTexts["settings.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Settings")
        let pounds = app.buttons["pounds"]
        let kilograms = app.buttons["kilograms"]
        XCTAssertTrue(kilograms.waitForExistence(timeout: 5))
        XCTAssertTrue(pounds.isSelected, "a new install in the US starts in pounds")
        kilograms.tap()
        XCTAssertTrue(kilograms.isSelected)
        XCTAssertFalse(pounds.isSelected)
        attachScreenshot(of: app, named: "Settings, kilograms")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(Self.element(saying: "kg moved", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(Self.element(saying: "lb moved", in: app).exists)
        attachScreenshot(of: app, named: "Today, in kilograms")
    }

    /// The first element whose label holds `text`.
    private static func element(saying text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
