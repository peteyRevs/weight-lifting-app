import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on the Library's screens: an
/// exercise's history (the bench press's, with the seed's four weeks of workouts, so its chart has points), New
/// exercise and Edit exercise. Their exclusions are `AuditProgramLibrary.exclusions` (measured, in the implementation
/// notes). One test per screen, or per way, each about 200 s or less on a Mac (S2b: the nightly allows 600 s a test,
/// and the runner is up to three times slower). Nightly only.
final class AuditLibrary: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The bench press's history over four weeks, from RECENTLY LOGGED.
    @MainActor
    func test_exerciseHistory_passesTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: AuditProgramLibrary.exclusions)
        try audit.threeWays(launching: AuditProgramLibrary.arguments + ["-LEDGER_UITEST_HISTORY", "4"]) { steps in
            let app = steps.app
            app.tabBars.buttons["Library"].tap()
            let recent = NSPredicate(format: "label == 'Barbell Bench Press' AND value CONTAINS ' sessions'")
            let row = app.buttons.matching(recent).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the bench press is in RECENTLY LOGGED")
            row.tap()
            XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 10), "its history")
            try audit.audit(steps, screen: "exercise history")
            // A catalog exercise's history offers no Edit (the lifter's own do): its one action is Back.
            audit.reach(steps, screen: "exercise history", [app.navigationBars.buttons["BackButton"]])
            audit.expectScrollsClear(steps, screen: "exercise history", anchor: "SESSION LOG", last: "Aug 24") {
                app.tabBars.firstMatch.frame.minY
            }
        }
    }

    /// New exercise, light and dark at the default size (`auditNewExercise`).
    @MainActor
    func test_newExercise_lightAndDark_passesTheAudit() throws {
        try auditNewExercise([.light, .dark])
    }

    /// New exercise at Accessibility XXXL: a way of its own, as the three would take over 200 s on a Mac.
    @MainActor
    func test_newExercise_atAccessibilityXXXL_passesTheAudit() throws {
        try auditNewExercise([.largest])
    }

    /// New exercise, empty; its last row, the movement pattern's chips ("Movement pattern: Core work"), scrolls clear
    /// of its foot (S2b).
    @MainActor
    private func auditNewExercise(_ ways: [AuditWay]) throws {
        let audit = ScreenAudit(for: self, exclusions: AuditProgramLibrary.exclusions)
        try audit.run(ways, launching: AuditProgramLibrary.arguments) { steps in
            let app = steps.app
            let name = Self.openNewExercise(steps)
            try audit.audit(steps, screen: "New exercise")
            let save = app.buttons["library.create.save"]
            audit.reach(steps, screen: "New exercise", [app.buttons["library.create.cancel"], save, name])
            let foot = PinnedPart.sheetFoot(save)
            audit.expectScrollsClear(steps, screen: "New exercise", anchor: "EQUIPMENT", last: "Movement pattern: ") {
                foot.minY
            }
        }
    }

    /// "Landmine Squeeze Press", made in New exercise, then its history's Edit.
    @MainActor
    func test_editExercise_passesTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: AuditProgramLibrary.exclusions)
        try audit.threeWays(launching: AuditProgramLibrary.arguments) { steps in
            let app = steps.app
            let name = Self.openNewExercise(steps)
            name.tap()
            name.typeText("Landmine Squeeze Press")
            let save = app.buttons["library.create.save"]
            save.tap()
            XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the sheet closed once saved")
            Self.openTheHistory(of: "Landmine Squeeze Press", steps)
            app.buttons["library.history.edit"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Edit exercise"].waitForExistence(timeout: 5), "Edit exercise")
            try audit.audit(steps, screen: "Edit exercise")
            audit.reach(steps, screen: "Edit exercise", [app.buttons["library.create.cancel"], save])
        }
    }

    /// The Library's "New exercise": its name field.
    @MainActor
    static func openNewExercise(_ steps: Steps) -> XCUIElement {
        let app = steps.app
        app.tabBars.buttons["Library"].tap()
        let new = app.buttons["New exercise"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10), "the Library")
        steps.scrollUntilHittable(new, back: true)
        new.tap()
        let name = app.textFields["library.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New exercise")
        return name
    }

    /// The Library's search, `exercise` typed, and its row: the exercise's history.
    @MainActor
    static func openTheHistory(of exercise: String, _ steps: Steps) {
        let app = steps.app
        let search = app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Search '")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the Library's search")
        search.tap()
        search.typeText(exercise)
        let row = app.buttons[exercise].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the Library lists \(exercise)")
        row.tap()
        XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 5), "its history")
    }
}
