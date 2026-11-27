import XCTest

/// F18 S7, the test plan's UI line: the watch's flows, each in one launch, through the screens a lifter taps, on a
/// watch that holds the seed program on one of its Mondays (`WatchSteps.seededMonday`) and the scripted Health store
/// every UI test gets. Nightly only, as the iPhone's `Flows`: the `PR-Watch` plan selects `Smoke`.
final class WatchFlows: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Start, a rep more, "Done set", the rest and "Skip", a second set and its rest, the session list, "End workout",
    /// "Save workout", the summary and "Done", back on the screen before a workout.
    @MainActor
    func test_wholeWorkout_startToSummaryAndBack() {
        let steps = WatchSteps(launching: WatchSteps.seededMonday, for: self)
        steps.start()
        XCTAssertEqual(steps.setLabel.label, "SET 1 OF 5")
        let heartRate = steps.element("workout.ready.heartRate")
        XCTAssertTrue(steps.wait(for: heartRate, "value == %@", "128 beats per minute"), "the scripted heart rate")
        let reps = steps.element("workout.ready.reps")
        XCTAssertTrue(reps.label.hasPrefix("× 5"), reps.label)
        steps.tap("workout.ready.reps.increase")
        XCTAssertTrue(steps.wait(for: reps, "label BEGINSWITH %@", "× 6"), "+ adds a rep: \(reps.label)")
        steps.attachScreenshot(named: "Set 1, six reps")

        for set in 1 ... 2 {
            steps.tap("workout.ready.doneSet")
            XCTAssertTrue(steps.reads(steps.restTitle, "REST"), "set \(set) starts its rest")
            steps.attachScreenshot(named: "Rest after set \(set)")
            steps.tap("workout.rest.skip")
            XCTAssertTrue(steps.reads(steps.setLabel, "SET \(set + 1) OF 5"), "Skip shows the next set")
        }

        steps.openEnd()
        let line = steps.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of '")).firstMatch
        XCTAssertTrue(line.exists, "the end overlay counts two sets logged")
        XCTAssertFalse(steps.app.buttons["workout.end.discard"].exists, "with sets logged it offers no Discard")
        steps.attachScreenshot(named: "End workout?")
        steps.tap("workout.end.save")

        let summary = steps.app.staticTexts["workout.summary.title"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Save shows the summary")
        XCTAssertEqual(summary.label, "WORKOUT DONE")
        XCTAssertTrue(steps.element("workout.summary.sets").label.hasPrefix("2"), "the summary counts two sets")
        steps.attachScreenshot(named: "Summary")
        steps.tap("workout.summary.done")
        XCTAssertTrue(steps.todayTitle.waitForExistence(timeout: 10), "Done returns to the screen before a workout")
        XCTAssertFalse(steps.setLabel.exists, "nothing is live")
    }

    /// A watch with no program (F18 criterion 16): "No program on watch" over the outlined line, which is no button.
    @MainActor
    func test_noProgram_saysSoAndOffersNoStart() {
        let steps = WatchSteps(for: self)
        XCTAssertEqual(steps.todayTitle.label, "No program on watch")
        let line = steps.element("today.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.hasPrefix("Open ") && line.label.hasSuffix(" on iPhone"), line.label)
        XCTAssertFalse(steps.app.buttons["today.start"].exists, "nothing to start")
        steps.attachScreenshot(named: "No program on watch")
    }

    /// A workout with no set logged: "End workout" offers "Discard" and no "Save workout"; Discard returns to the
    /// screen before a workout, with today's "Start" again.
    @MainActor
    func test_emptyWorkout_endAndDiscard() {
        let steps = WatchSteps(launching: WatchSteps.seededMonday, for: self)
        steps.start()
        steps.openEnd()
        XCTAssertFalse(steps.app.buttons["workout.end.save"].exists, "no set logged, nothing to save")
        steps.attachScreenshot(named: "End workout? with no set")
        steps.tap("workout.end.discard")
        XCTAssertTrue(steps.reads(steps.todayTitle, WatchSteps.upperA), "Discard returns to today's day")
        XCTAssertTrue(steps.app.buttons["today.start"].waitForExistence(timeout: 5), "and offers its Start again")
        XCTAssertFalse(steps.setLabel.exists, "nothing is live")
    }
}
