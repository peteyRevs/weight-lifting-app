import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on a finished workout's
/// detail and its edit-sets sheet (with the seed's four weeks of history); Settings's screens are `AuditSettings`'s,
/// with these exclusions. On the seed program at noon on Wednesday of its week 5.
/// What the audit reports and is excused is each screen's exclusions' (measured, in the implementation notes);
/// anything else fails. Each test takes about 200 s or less on a Mac (S2b: the nightly allows 600 s a test, and the
/// runner is up to three times slower). Nightly only.
final class AuditHistorySettings: XCTestCase {
    static let arguments = ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z", "-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The History list's newest workout (that Monday's Upper A).
    @MainActor
    func test_workoutDetail_passesTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.threeWays(launching: Self.arguments + ["-LEDGER_UITEST_HISTORY", "4"]) { steps in
            let app = steps.app
            Self.openTheNewestWorkout(steps)
            try audit.audit(steps, screen: "workout detail")
            let edit = app.buttons["history.workout.edit"]
            audit.reach(steps, screen: "workout detail", [app.buttons["history.workout.delete"], edit])
            audit.expectScrollsClear(steps, screen: "workout detail", anchor: "LOGGED", last: "Delete workout") {
                app.tabBars.firstMatch.frame.minY
            }
        }
    }

    /// The edit-sets sheet, light and dark at the default size (`auditEditSets`).
    @MainActor
    func test_editSets_lightAndDark_passesTheAudit() throws {
        try auditEditSets([.light, .dark])
    }

    /// The edit-sets sheet at Accessibility XXXL: a way of its own, as the three would take over 200 s on a Mac.
    @MainActor
    func test_editSets_atAccessibilityXXXL_passesTheAudit() throws {
        try auditEditSets([.largest])
    }

    /// The newest workout's "Edit": the edit-sets sheet.
    @MainActor
    private func auditEditSets(_ ways: [AuditWay]) throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.run(ways, launching: Self.arguments + ["-LEDGER_UITEST_HISTORY", "4"]) { steps in
            let app = steps.app
            Self.openTheNewestWorkout(steps)
            let edit = app.buttons["history.workout.edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            edit.tap()
            XCTAssertTrue(app.buttons["history.edit.save"].waitForExistence(timeout: 5), "the edit-sets sheet")
            let foot = PinnedPart.sheetFoot(app.buttons["history.edit.save"])
            try audit.audit(steps, screen: "edit sets", pinned: foot)
            audit.reach(steps, screen: "edit sets", [app.buttons["history.edit.cancel"], foot.top])
            // The sheet's last line: the reps of Cable Lateral Raise's last set.
            audit.expectScrollsClear(steps, screen: "edit sets", anchor: "Set 1 weight", last: "16") { foot.minY }
        }
    }

    /// The History tab, then its newest workout's detail.
    @MainActor
    static func openTheNewestWorkout(_ steps: Steps) {
        let app = steps.app
        app.tabBars.buttons["History"].tap()
        let newest = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10), "History lists the seeded workouts")
        newest.tap()
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "its detail")
    }
}

extension AuditHistorySettings {
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
