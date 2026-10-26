import XCTest

/// F12 S2 adversarial round 1 (G2): the DoD's VoiceOver pass, read from the running app. A sample workout with one
/// set is saved, then Library → its exercise in RECENTLY LOGGED opens the history. The accessibility tree under
/// the navigation bar is written to the log in reading order (`AXDUMP` lines: type, label, value, identifier) and
/// kept with the result; the essentials are asserted: the heading, the three stats, the chart as one element at
/// the default size and as a list of weeks at Accessibility XXXL, SESSION LOG, and the session as one button.
/// Nightly only: the `PR` plan selects `Smoke`.
final class HistoryVoiceOverAdversarial: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_history_defaultSize_readsHeadingStatsChartAndLog() {
        let app = openHistory(textSize: nil)
        let tree = dump(app, named: "default size")
        XCTAssertTrue(app.staticTexts["library.history.title"].exists)
        XCTAssertTrue(tree.contains { $0.label.hasSuffix("1RM est") }, "the estimate's tile")
        XCTAssertTrue(tree.contains { $0.label.hasSuffix("best set") }, "the best set's tile")
        XCTAssertTrue(tree.contains { $0.label.hasSuffix("sessions") || $0.label.hasSuffix("session") })
        // XCUITest also lists the texts inside a combined or ignored element, which VoiceOver does not visit, so
        // the chart is checked as its one element, not by the absence of its week labels.
        XCTAssertTrue(
            tree.contains { $0.type == .other && $0.label == "Estimated 1RM by week" },
            "the chart is one element"
        )
        XCTAssertTrue(tree.contains { $0.label == "SESSION LOG" })
        let sessions = tree.filter { $0.type == .button && $0.value.contains("×") }
        XCTAssertEqual(sessions.count, 1, "the one saved workout is one button")
    }

    @MainActor
    func test_history_accessibilityXXXL_readsTheWeeksAsAList() {
        let app = openHistory(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        var tree = dump(app, named: "Accessibility XXXL")
        // The list may lie below the fold: scroll once and read again.
        if !tree.contains(where: { $0.label.hasPrefix("W8") }) {
            app.swipeUp()
            tree = dump(app, named: "Accessibility XXXL, scrolled")
        }
        XCTAssertFalse(tree.contains { $0.label == "Estimated 1RM by week" }, "no bars at accessibility sizes")
        XCTAssertTrue(tree.contains { $0.label.hasPrefix("W8, ") }, "the current week is a row of the list")
    }

    /// Criterion 11: a session of the log opens its workout, which until F13 selects the History tab, once.
    @MainActor
    func test_history_sessionTap_selectsTheHistoryTab() {
        let app = openHistory(textSize: nil)
        let session = app.buttons.matching(NSPredicate(format: "value CONTAINS '×'")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5), "the saved session is a button")
        session.tap()
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: history)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "the History tab is selected")
    }

    // MARK: Helpers

    struct Stop: CustomStringConvertible {
        let type: XCUIElement.ElementType
        let label: String
        let value: String
        let identifier: String
        let frame: CGRect

        var description: String {
            let place = "y \(Int(frame.minY)) h \(Int(frame.height))"
            return "AXDUMP \(type.rawValue) | \(label) | \(value) | \(identifier) | \(place)"
        }
    }

    /// The app on its saved sample workout's history, at `textSize`.
    @MainActor
    private func openHistory(textSize: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        app.staticTexts["today.title"].press(forDuration: 1)
        let sample = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        let logSet = app.buttons["Log set 1"]
        XCTAssertTrue(logSet.waitForExistence(timeout: 10))
        logSet.tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let done = app.buttons["workout.receipt.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons.matching(NSPredicate(format: "value CONTAINS '1 session'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved exercise is in RECENTLY LOGGED")
        row.tap()
        XCTAssertTrue(app.staticTexts["library.history.title"].waitForExistence(timeout: 10))
        return app
    }

    /// Every element with something to read, in the tree's order, logged and kept with the result.
    @MainActor
    private func dump(_ app: XCUIApplication, named name: String) -> [Stop] {
        var stops: [Stop] = []
        func walk(_ element: any XCUIElementSnapshot) {
            let value = (element.value as? String) ?? ""
            if !element.label.isEmpty || !value.isEmpty {
                stops.append(Stop(
                    type: element.elementType,
                    label: element.label,
                    value: value,
                    identifier: element.identifier,
                    frame: element.frame
                ))
            }
            element.children.forEach(walk)
        }
        if let snapshot = try? app.snapshot() {
            walk(snapshot)
        }
        let text = stops.map(\.description).joined(separator: "\n")
        print("AXDUMP begin \(name)\n\(text)\nAXDUMP end \(name)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "Accessibility tree, \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = name
        picture.lifetime = .keepAlways
        add(picture)
        return stops
    }
}
