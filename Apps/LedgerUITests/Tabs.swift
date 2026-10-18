import XCTest

/// F09 S1 criteria 1, 2 and 5, on screen: the root shows four tabs, Today · Program · Library · History, with Today
/// selected on launch; each tab shows its own screen, whose title names it; and the tab bar's buttons are what
/// VoiceOver reads, each by its title, the selected one marked selected. Nightly only: the `PR` plan selects `Smoke`.
final class Tabs: XCTestCase {
    private static let titles = ["Today", "Program", "Library", "History"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_fourTabs_todaySelected_inTheBarsOrder() {
        let app = launch()
        let buttons = Self.titles.map { app.tabBars.buttons[$0] }
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 10))

        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertEqual(buttons.map(\.label), Self.titles)
        XCTAssertEqual(buttons.map(\.frame.minX), buttons.map(\.frame.minX).sorted(), "left to right, in this order")
        XCTAssertEqual(buttons.map(\.isSelected), [true, false, false, false])
        XCTAssertTrue(app.staticTexts["today.title"].exists)
        attachScreenshot(of: app, named: "Today")
    }

    @MainActor
    func test_eachTab_showsItsOwnScreen_andTodayKeepsItsTitle() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))

        for (index, title) in Self.titles.enumerated().dropFirst() {
            app.tabBars.buttons[title].tap()
            let heading = app.staticTexts["\(title.lowercased()).title"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), title)
            XCTAssertEqual(heading.label, title)
            XCTAssertEqual(
                Self.titles.map { app.tabBars.buttons[$0].isSelected },
                Self.titles.indices.map { $0 == index },
                "only \(title) is selected"
            )
            XCTAssertFalse(app.staticTexts["today.title"].exists)
            attachScreenshot(of: app, named: title)
        }

        app.tabBars.buttons["Today"].tap()
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertEqual(today.label, "Today")
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        return app
    }

    /// Kept with the result, so a run shows the screens it checked.
    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
