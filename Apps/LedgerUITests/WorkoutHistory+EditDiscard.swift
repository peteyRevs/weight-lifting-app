import XCTest

extension WorkoutHistory {
    /// F13 S3 adversarial (G2): what leaves a changed sheet without saving. "Cancel" and a swipe each discard the step,
    /// unasked (notes, decision 8), and reopening shows the stored value: the sheet never wrote.
    @MainActor
    func test_editCancelAndSwipe_discardTheStep() throws {
        let app = launchWithASavedWorkout()
        app.tabBars.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS ' pounds'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let edit = app.buttons["history.workout.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let weight = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Set 1 weight'")).firstMatch
        let save = app.buttons["history.edit.save"]

        func stepInTheSheet() throws -> String {
            edit.tap()
            XCTAssertTrue(weight.waitForExistence(timeout: 5))
            let before = try XCTUnwrap(weight.value as? String)
            weight.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            XCTAssertNotEqual(weight.value as? String, before, "the weight stepped")
            XCTAssertTrue(save.isEnabled)
            return before
        }

        let stored = try stepInTheSheet()
        app.buttons["history.edit.cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Cancel took the sheet down")
        XCTAssertFalse(weight.exists)
        XCTAssertEqual(try stepInTheSheet(), stored, "Cancel stored nothing")
        app.swipeDown(velocity: .fast)
        let gone = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: weight)], timeout: 5)
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a swipe took a changed sheet down, unasked")
        edit.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, stored, "the swipe stored nothing")
        XCTAssertFalse(save.isEnabled)
    }
}
