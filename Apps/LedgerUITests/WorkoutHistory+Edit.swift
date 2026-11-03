import XCTest

extension WorkoutHistory {
    /// F13 S3, criterion 4: "Edit" opens every logged set; Save is off until a weight is stepped; once saved, the sheet
    /// comes down, the detail's moved tile changes without navigating, and back on the list the row's volume does too.
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
        let moved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH ' lb moved'")).firstMatch
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        let movedBefore = moved.label
        edit.tap()
        let save = app.buttons["history.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "nothing changed yet")
        let weight = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Set 1 weight'")).firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        let weightBefore = try XCTUnwrap(weight.value as? String)
        weight.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        expect(weight, "value != %@", weightBefore, timeout: 5)
        expect(save, "isEnabled == true", timeout: 5)
        attachScreenshot(of: app, named: "Edit sets, changed")
        save.tap()
        expect(save, "exists == false", timeout: 5)
        expect(moved, "label != %@", movedBefore, timeout: 10)
        app.navigationBars.buttons.firstMatch.tap()
        expect(row, "value != %@", volumeBefore, timeout: 10)
    }

    /// Waits until `element` meets `format`, re-reading it until then.
    private func expect(_ element: XCUIElement, _ format: String, _ arguments: String..., timeout: TimeInterval) {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
    }
}
