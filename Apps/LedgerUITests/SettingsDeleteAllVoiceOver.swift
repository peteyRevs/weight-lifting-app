import XCTest

/// F14 S3, the Definition of Done's VoiceOver check (G3 SF3), on the simulator: what the accessibility tree offers, in
/// reading order, for "Delete all data" on and off, its warning, and its sheet empty and typed; and the system's
/// accessibility audit of the sheet. Each state's stops are attached to the result as text, so a run shows what is
/// read. Nightly only: the `PR` plan selects `Smoke`.
final class SettingsDeleteAllVoiceOver: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The stops of `root` VoiceOver can land on, top to bottom then leading to trailing: "button 'Cancel'". Only those
    /// on top are listed: the page under a sheet is still in the tree, but VoiceOver stays in the sheet.
    @MainActor
    private func stops(in root: XCUIElement) -> [String] {
        let kinds: [(XCUIElement.ElementType, String)] = [
            (.staticText, "text"), (.button, "button"), (.textField, "field"), (.activityIndicator, "progress")
        ]
        let found = kinds.flatMap { type, name in
            let onTop = root.descendants(matching: type).allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            return onTop.map { element in
                (
                    element.frame,
                    "\(name) '\(element.label)'" + (element.isEnabled ? "" : " (dimmed)")
                        + ((element.value as? String).map { $0.isEmpty ? "" : " = '\($0)'" } ?? "")
                )
            }
        }
        return found.sorted { ($0.0.minY, $0.0.minX) < ($1.0.minY, $1.0.minX) }.map(\.1)
    }

    @MainActor
    private func record(_ lines: [String], named name: String) {
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openSettingsRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        let row = app.buttons["settings.deleteAll"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0 ..< 4 where !row.isHittable {
            app.swipeUp()
        }
        return row
    }

    @MainActor
    func test_rowWarningAndSheet_readInOrder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        let row = openSettingsRow(in: app)
        record(["button '\(row.label)'" + (row.isEnabled ? "" : " (dimmed)")], named: "Row, on")
        XCTAssertEqual(row.label, "Delete all data")
        XCTAssertTrue(row.isEnabled)
        row.tap()

        let warning = app.alerts.firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        let alert = stops(in: warning)
        record(alert, named: "Warning")
        XCTAssertEqual(alert.first, "text 'Delete all data?'")
        XCTAssertTrue(alert.contains("button 'Cancel'"))
        XCTAssertTrue(alert.contains("button 'Continue'"))
        warning.buttons["Continue"].tap()

        let field = app.textFields["settings.deleteAll.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let empty = stops(in: app)
        record(empty, named: "Sheet, empty")
        XCTAssertTrue(empty.contains("button 'Delete everything' (dimmed)"))
        XCTAssertEqual(field.label, "Type DELETE to confirm")
        try app.performAccessibilityAudit(for: [.dynamicType, .sufficientElementDescription, .hitRegion])

        field.tap()
        field.typeText("delete")
        let typed = stops(in: app)
        record(typed, named: "Sheet, typed")
        XCTAssertTrue(typed.contains("button 'Delete everything'"))
        app.buttons["settings.deleteAll.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Cancel closes the sheet")
    }

    @MainActor
    func test_rowWhileAWorkoutIsInProgress_isDimmedAndSaysWhy() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        app.staticTexts["today.title"].press(forDuration: 1)
        let sample = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))
        let row = openSettingsRow(in: app)
        record(["button '\(row.label)'" + (row.isEnabled ? "" : " (dimmed)")], named: "Row, off")
        XCTAssertEqual(row.label, "Delete all data, Finish or discard your workout first")
        XCTAssertFalse(row.isEnabled)
    }
}
