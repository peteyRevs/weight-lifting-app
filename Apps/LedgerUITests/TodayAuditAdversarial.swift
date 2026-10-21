import XCTest

/// F09 S5 adversarial round 1 (G2): the system's accessibility audit on every state of Today a UI test can
/// reach, in the running app: a session day, the same day with a workout minimized (Resume), a rest day, its
/// off-schedule sheet. (Round 1 also audited a fresh database's "No program yet", in light, in dark and at an
/// accessibility text size; F08 replaced those with onboarding's audits.)
///
/// Each issue is recorded with the element's type, label and frame, and a picture of the element is kept
/// with the result, so that a "text clipped" can be looked at. Nightly only.
///
/// **Round 2 (criterion 19).** Round 1 excluded nothing and judged the four issues the system reports false
/// positives (FINDING F09-S5-1 to 4, in the notes). They are now excluded, by the system's words for the
/// issue and the element's label, in `TodayAuditExclusions`, which holds the measurement and the reason of
/// each. Anything else the system reports fails its test.
final class TodayAuditAdversarial: XCTestCase {
    /// Thursday of week 5 of the seed program: nothing is scheduled.
    private static let restDay = "2026-09-17T12:00:00Z"
    /// Wednesday of week 5: Lower A.
    private static let sessionDay = "2026-09-16T12:00:00Z"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // Sanctioned edit of F08 S2/S3 (ruling R3): the three audits of a fresh database's "No program yet" are gone.
    // A fresh database now opens on onboarding, whose audits, light, dark and at an accessibility size, are
    // `OnboardingAdversarial+Audit`'s; these tests launch with the seed program.

    @MainActor
    func test_sessionDay_upNextThenResume_passTheAudit() throws {
        let app = launch(at: Self.sessionDay)
        seedTheProgram(in: app)
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let upNext = try audit(app, state: "up next")

        start.tap()
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(app.buttons["Resume workout"].waitForExistence(timeout: 10))
        let resume = try audit(app, state: "resume")
        XCTAssertEqual(upNext + resume, [])
    }

    @MainActor
    func test_sessionDay_dark_passesTheAudit() throws {
        let before = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = before }
        XCUIDevice.shared.appearance = .dark
        let app = launch(at: Self.sessionDay)
        seedTheProgram(in: app)
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 10))
        XCTAssertEqual(try audit(app, state: "up next, dark"), [])
    }

    /// The audit's "Contrast failed" on the page's last line is the floating tab bar drawn over it while the
    /// page rests at its top. That is a false positive only if the line can be brought clear of the bar: here
    /// the page is scrolled to its end and the line must stand whole above the bar, at the default text size
    /// and at an accessibility size.
    @MainActor
    func test_sessionDay_theLastLineScrollsClearOfTheTabBar() {
        for textSize in [nil, "UICTContentSizeCategoryAccessibilityL"] {
            let app = launch(at: Self.sessionDay, textSize: textSize)
            seedTheProgram(in: app)
            XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 10))
            let last = app.staticTexts["No sessions yet. Your first workout lands here."]
            XCTAssertTrue(last.exists)
            for _ in 0 ..< 6 {
                app.swipeUp(velocity: .fast)
            }
            let bar = app.tabBars.firstMatch.frame
            attach(app.screenshot(), named: "scrolled to the end, \(textSize ?? "default size")")
            XCTAssertLessThanOrEqual(last.frame.maxY, bar.minY, "\(textSize ?? "default"): under the tab bar")
            app.terminate()
        }
    }

    @MainActor
    func test_restDay_andItsSheet_passTheAudit() throws {
        let app = launch(at: Self.restDay)
        seedTheProgram(in: app)
        let offSchedule = app.buttons["Train off-schedule"]
        XCTAssertTrue(offSchedule.waitForExistence(timeout: 10))
        let card = try audit(app, state: "rest day")

        offSchedule.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        let sheet = try audit(app, state: "off-schedule sheet")
        XCTAssertEqual(card + sheet, [])
    }
}

private extension TodayAuditAdversarial {
    /// The system's audit of what is on screen, every type, less `TodayAuditExclusions`' four. One line per issue: the
    /// state,
    /// the issue, the element's type, label and frame. A picture of the screen and of each element is kept.
    @MainActor
    func audit(_ app: XCUIApplication, state: String) throws -> [String] {
        attach(app.screenshot(), named: "\(state): screen")
        var issues: [String] = []
        var excluded: [String] = []
        var elements: [(String, XCUIElement)] = []
        let tabBar = app.tabBars.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            var line = "\(state): \(issue.compactDescription)"
            if let element = issue.element {
                let frame = element.frame
                let box = "x \(Int(frame.minX)) y \(Int(frame.minY)) w \(Int(frame.width)) h \(Int(frame.height))"
                line += " [\(element.elementType.rawValue) \"\(element.label)\" \(box)]"
                elements.append(("\(state): \(issue.compactDescription): \(element.label)", element))
            } else {
                line += " [no element]"
            }
            let isKnown = issue.element.map { element in
                TodayAuditExclusions.isKnownFalsePositive(
                    issue: issue.compactDescription, label: element.label, frame: element.frame, tabBar: tabBar
                )
            } ?? false
            if isKnown {
                excluded.append(line)
            } else {
                issues.append(line)
            }
            return true
        }
        // Kept with the result: what was excluded in this state, so a run shows it is still only these.
        let list = XCTAttachment(string: excluded.joined(separator: "\n"))
        list.name = "\(state): excluded"
        list.lifetime = .keepAlways
        add(list)
        for (name, element) in elements where element.exists {
            attach(element.screenshot(), named: name)
        }
        return issues
    }

    /// The app on a fresh database, its clock moved so that the launch happens at `instant`.
    @MainActor
    func launch(at instant: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", instant]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        return app
    }

    /// Saves the seed program as the active one, as `Today`'s tests do: the Debug menu's sample workout saves
    /// it and starts its first day, which is then discarded.
    @MainActor
    func seedTheProgram(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        app.buttons["workout.header.finish"].tap()
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
