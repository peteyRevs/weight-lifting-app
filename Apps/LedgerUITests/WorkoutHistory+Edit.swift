import XCTest

extension WorkoutHistory {
    /// F13 S3, criterion 4: "Edit" opens every logged set; Save is off until a weight is stepped; once saved, the sheet
    /// comes down and the detail and the list show the new volume, without navigating or relaunching.
    @MainActor
    func test_editASet_showsInTheDetailAndTheList() throws {
        let app = launchWithASavedWorkout()
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let volumeBefore = try XCTUnwrap(row.value as? String)
        row.tap()
        let edit = app.buttons["history.workout.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let save = app.buttons["history.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "nothing changed yet")
        let weight = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Set 1 weight'")).firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        let weightBefore = try XCTUnwrap(weight.value as? String)
        weight.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertNotEqual(weight.value as? String, weightBefore, "the weight stepped")
        XCTAssertTrue(save.isEnabled)
        attachScreenshot(of: app, named: "Edit sets, changed")
        save.tap()
        XCTAssertTrue(app.staticTexts["history.workout.title"].waitForExistence(timeout: 5), "the sheet came down")
        XCTAssertFalse(save.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertNotEqual(row.value as? String, volumeBefore, "the list shows the edit")
    }
}
