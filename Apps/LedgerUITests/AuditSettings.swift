import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on Settings and its "Bar and
/// plates" sheet, with the scrolls-clear proofs of Settings, Bar and plates and Delete all data's sheet. On the seed
/// program at noon on Wednesday of its week 5; the exclusions are `AuditHistorySettings.exclusions` (measured, in the
/// implementation notes). A class of its own (S2b), so the nightly can place it apart from the History's. Nightly only.
final class AuditSettings: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Today's gear: Settings; then "Bar and plates" and its sheet.
    @MainActor
    func test_settingsAndBarAndPlates_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: AuditHistorySettings.exclusions)
        try audit.threeWays(launching: AuditHistorySettings.arguments) { steps in
            let app = steps.app
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5), "Settings")
            try audit.audit(steps, screen: "Settings")
            let plates = steps.element(startingWith: "Bar and plates")
            let rows = [app.buttons["settings.deleteAll"], app.buttons["settings.export"], plates]
            audit.reach(steps, screen: "Settings", rows)

            steps.scrollUntilHittable(plates)
            plates.tap()
            let cancel = app.buttons["settings.plates.cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Bar and plates")
            try audit.audit(steps, screen: "Bar and plates")
            let done = PinnedPart.sheetFoot(app.buttons["settings.plates.done"])
            audit.reach(steps, screen: "Bar and plates", [cancel, done.top])
            // The sheet's last row scrolls clear of its foot (S2b).
            audit.expectScrollsClear(steps, screen: "Bar and plates", anchor: "Bar", last: "Reset to standard") {
                done.minY
            }
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "the sheet went down")
            try expectDeleteAllScrollsClear(audit, steps)

            // The version line, "Ledger 0.21.1 · build 1", whose version changes: matched by its start.
            audit.expectScrollsClear(steps, screen: "Settings", anchor: "TRAINING", last: "Ledger ") {
                app.tabBars.firstMatch.frame.minY
            }
        }
    }
}

extension AuditSettings {
    /// "Delete all data"'s sheet: its last row, the typed word's field, scrolls clear of its foot (S2b). Not audited
    /// here: `SettingsDeleteAllVoiceOver` audits it.
    @MainActor
    private func expectDeleteAllScrollsClear(_ audit: ScreenAudit, _ steps: Steps) throws {
        let app = steps.app
        let row = app.buttons["settings.deleteAll"]
        steps.scrollUntilHittable(row)
        row.tap()
        let warning = app.alerts["Delete all data?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "the warning")
        warning.buttons["Continue"].tap()
        let foot = PinnedPart.sheetFoot(app.buttons["settings.deleteAll.confirm"])
        XCTAssertTrue(foot.top.waitForExistence(timeout: 5), "Delete all data's sheet")
        audit.reach(steps, screen: "Delete all data", [foot.top])
        audit.expectScrollsClear(
            steps, screen: "Delete all data", anchor: "This can't be undone.", last: "Type DELETE to confirm"
        ) { foot.minY }
        let cancel = app.buttons["Cancel"]
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "the sheet went down")
    }
}
