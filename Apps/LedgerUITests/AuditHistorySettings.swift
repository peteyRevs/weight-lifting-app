import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on a finished workout's
/// detail and its edit-sets sheet (with the seed's four weeks of history), and on Settings and its "Bar and plates"
/// sheet. On the seed program at noon on Wednesday of its week 5. What the audit reports and is excused is each
/// screen's exclusions' (measured, in the implementation notes); anything else fails. Nightly only.
final class AuditHistorySettings: XCTestCase {
    private static let arguments = ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z", "-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The History list's newest workout (that Monday's Upper A), then its "Edit".
    @MainActor
    func test_workoutDetailAndEditSets_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.threeWays(launching: Self.arguments + ["-LEDGER_UITEST_HISTORY", "4"]) { steps in
            let app = steps.app
            XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10))
            app.tabBars.buttons["History"].tap()
            let newest = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
            XCTAssertTrue(newest.waitForExistence(timeout: 10), "History lists the seeded workouts")
            newest.tap()
            XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "its detail")
            try audit.audit(steps, screen: "workout detail")
            let edit = app.buttons["history.workout.edit"]
            audit.reach(steps, screen: "workout detail", [app.buttons["history.workout.delete"], edit])
            audit.expectScrollsClear(steps, screen: "workout detail", anchor: "LOGGED", last: "Delete workout") {
                app.tabBars.firstMatch.frame.minY
            }

            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            edit.tap()
            XCTAssertTrue(app.buttons["history.edit.save"].waitForExistence(timeout: 5), "the edit-sets sheet")
            let foot = PinnedPart.sheetFoot(app.buttons["history.edit.save"])
            try audit.audit(steps, screen: "edit sets", pinned: foot)
            audit.reach(steps, screen: "edit sets", [app.buttons["history.edit.cancel"], foot.top])
            // The sheet's last line: the reps of Cable Lateral Raise's last set.
            audit.expectScrollsClear(
                steps, screen: "edit sets", anchor: "Set 1 weight", last: "16"
            ) { foot.minY }
        }
    }

    /// Today's gear: Settings; then "Bar and plates" and its sheet.
    @MainActor
    func test_settingsAndBarAndPlates_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.threeWays(launching: Self.arguments) { steps in
            let app = steps.app
            XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10))
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

extension AuditHistorySettings {
    /// "Delete all data"'s sheet: its last row, the typed word's field, scrolls clear of its foot (S2b). Not audited
    /// here: `SettingsDeleteAllVoiceOver` audits it.
    @MainActor
    private func expectDeleteAllScrollsClear(_ audit: ScreenAudit, _ steps: Steps) throws {
        let app = steps.app
        let row = app.buttons["settings.deleteAll"]
        steps.scrollIntoReach(row)
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

    /// The measured exclusions of the workout's detail, its edit sheet, Settings and Bar and plates (F15-S2-3 to 8).
    static var exclusions: [ScreenExclusion] {
        [
            .eyebrows(["workout detail": ["TIME", "SETS", "LB MOVED", "LOGGED"], "Settings": ["TRAINING"]]),
            .shortLines([
                "workout detail": ["Monday, September 14", "Upper A — Push focus", "8 new PRs this session", "LB MOVED"]
            ]),
            .underTheTabBar(on: ["workout detail", "Settings"]),
            .underThePinnedPart(on: ["edit sets"]),
            systemEditButton
        ]
    }

    /// F15-S2-8: the detail's "Edit", a plain `Button` in the navigation bar that the system draws on its own glass
    /// at its own size. Its picture's ink is (0, 0, 0) on the glass's (253, 253, 249), 20.5:1, where the audit
    /// says "Contrast failed"; and the system caps a bar button's text size, which it reports as Dynamic Type
    /// "partially unsupported". By identifier: the same issues on a button of the page fail.
    static var systemEditButton: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-8", issue: "the system's bar button Edit") {
            ["Contrast failed", "Dynamic Type font sizes are partially unsupported"].contains($0.summary)
                && $0.elementType == .button && $0.identifier == "history.workout.edit" && $0.screen == "workout detail"
        }
    }
}
