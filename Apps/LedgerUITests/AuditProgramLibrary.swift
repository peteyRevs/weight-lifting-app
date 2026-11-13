import XCTest

/// F15 S2, criterion 6 (C7): the system's accessibility audit, three ways (`AuditWay`), on the Program tab's Day
/// editor and its exercise-picker sheet, and on the Library's New exercise, Edit exercise and an exercise's history.
/// On the seed program at noon on Wednesday of its week 5; the history with the seed's four weeks of workouts
/// (`-LEDGER_UITEST_HISTORY 4`), so its chart has points. What the audit reports and is excused is each screen's
/// exclusions' (measured, in the implementation notes); anything else fails. Nightly only.
final class AuditProgramLibrary: XCTestCase {
    private static let arguments = ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z", "-LEDGER_UITEST_PROGRAM", "seed"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lower A's Day editor from the builder, then its "+ Add exercise from library" sheet.
    @MainActor
    func test_dayEditorAndItsPicker_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions)
        try audit.threeWays(launching: Self.arguments) { steps in
            let app = steps.app
            XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10))
            app.tabBars.buttons["Program"].tap()
            XCTAssertTrue(app.textFields["Program name"].waitForExistence(timeout: 10), "the builder")
            let card = app.buttons["Lower A — Squat focus"].firstMatch
            steps.scrollUntilHittable(card)
            card.tap()
            XCTAssertTrue(app.textFields["Day name"].waitForExistence(timeout: 5), "the Day editor")
            try audit.audit(steps, screen: "Day editor")
            audit.expectScrollsClearOfTheTabBar(steps, screen: "Day editor")

            let open = app.buttons["+ Add exercise from library"]
            steps.scrollUntilHittable(open)
            open.tap()
            let search = app.textFields["Search exercises"]
            XCTAssertTrue(search.waitForExistence(timeout: 5), "the exercise picker")
            try audit.audit(steps, screen: "exercise picker", pinned: app.buttons["Select exercises to add"])
        }
    }

    /// The bench press's history over four weeks, then New exercise, saved, and its history's Edit.
    @MainActor
    func test_historyNewAndEditExercise_passTheAudit() throws {
        let audit = ScreenAudit(for: self, exclusions: Self.exclusions, open: [Self.truncatedName])
        try audit.threeWays(launching: Self.arguments + ["-LEDGER_UITEST_HISTORY", "4"]) { steps in
            let app = steps.app
            XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10))
            app.tabBars.buttons["Library"].tap()
            let recent = NSPredicate(format: "label == 'Barbell Bench Press' AND value CONTAINS ' sessions'")
            let row = app.buttons.matching(recent).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the bench press is in RECENTLY LOGGED")
            row.tap()
            let title = app.staticTexts["library.history.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 10), "its history")
            try audit.audit(steps, screen: "exercise history")
            audit.expectScrollsClearOfTheTabBar(steps, screen: "exercise history")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(title.waitForNonExistence(timeout: 5), "back on the Library")

            // The header's "New exercise" is at the page's top, which the tap on a lower row scrolled away.
            let new = app.buttons["New exercise"].firstMatch
            steps.scrollUntilHittable(new, back: true)
            new.tap()
            let name = app.textFields["library.create.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5), "New exercise")
            try audit.audit(steps, screen: "New exercise")
            name.tap()
            name.typeText("Landmine Squeeze Press")
            app.buttons["library.create.save"].tap()
            XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the sheet closed once saved")
            openTheHistory(of: "Landmine Squeeze Press", steps)
            app.buttons["library.history.edit"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Edit exercise"].waitForExistence(timeout: 5), "Edit exercise")
            try audit.audit(steps, screen: "Edit exercise")
        }
    }

    /// The Library's search, `exercise` typed, and its row: the exercise's history.
    @MainActor
    private func openTheHistory(of exercise: String, _ steps: Steps) {
        let app = steps.app
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(exercise)
        let row = app.buttons[exercise].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the Library lists \(exercise)")
        row.tap()
        XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 5), "its history")
    }
}

extension AuditProgramLibrary {
    static let screens: Set = ["Day editor", "exercise picker", "exercise history", "New exercise", "Edit exercise"]

    /// The measured exclusions of the Day editor, its picker and the Library's screens (F15-S2-3 to 8, the notes).
    static var exclusions: [ScreenExclusion] {
        [
            .eyebrows([
                "DAY 2 OF 4",
                "SUPERSET",
                "NAME",
                "EQUIPMENT",
                "PRIMARY MUSCLE",
                "MOVEMENT PATTERN",
                "SECONDARY MUSCLES",
                "ESTIMATED 1RM · 8 WEEKS",
                "SESSION LOG"
            ], on: screens),
            // "Day name" is the day's name field, drawn in the title role (1.0 line): whole in every picture.
            .shortLines([
                "+ Add exercise from library",
                "2 exercises back to back · rest after B",
                "Day name",
                "Select exercises to add",
                "PRIMARY MUSCLE",
                "MOVEMENT PATTERN",
                "SECONDARY MUSCLES",
                "Barbell Bench Press",
                "ESTIMATED 1RM · 8 WEEKS"
            ], on: screens),
            .underTheTabBar(on: ["Day editor", "exercise history"]),
            .underThePinnedPart(on: ["exercise picker"]),
            .accentButtons(["Save"], on: ["New exercise", "Edit exercise"]),
            wholeName
        ]
    }

    /// F15-S2-4 on Edit exercise's name field (its label is empty, so by identifier): at the default size the
    /// field's picture shows "Landmine Squeeze Press" whole, light and dark. At Accessibility XXXL it is cut:
    /// `truncatedName`.
    static var wholeName: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on the whole name, Edit exercise") {
            $0.summary == "Text clipped" && $0.identifier == "library.create.name" && $0.way != .largest
                && $0.screen == "Edit exercise"
        }
    }

    /// F15-S2-11, open: at Accessibility XXXL the one-line name field draws "Landmine Squ…". A real finding, an
    /// expected failure until its own fix: the follow-up PR after S2 ports Program's `NameField` pattern (the
    /// unfocused name drawn as wrapping text under the field) or moves `NameField` into LedgerDesign.
    static var truncatedName: ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-11", issue: "the name is cut at Accessibility XXXL, Edit exercise") {
            $0.summary == "Text clipped" && $0.identifier == "library.create.name" && $0.way == .largest
                && $0.screen == "Edit exercise"
        }
    }
}
