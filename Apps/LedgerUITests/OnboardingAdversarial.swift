import XCTest

/// F08 S3 adversarial round 1 (G2), for what only the running app shows (criteria 1, 3, 7 and 8): a fresh
/// install's first screen; each step's stops in VoiceOver's order inside the real scroll view at the largest text
/// size (the one reader of that tree: F8-S2-5); a step opening at its top after the one before was scrolled; the
/// picks through "Back" and through leaving the app; "Skip setup" from each step and "Start training", each
/// landing on Today with the program stored that the picks ask for; and the system's accessibility audit of each
/// step, in light and dark (`OnboardingAdversarial+Audit.swift`). Nightly only, as every UI test but `Smoke` is.
/// It launches through the suite's `XCUIApplication.fresh(_:)` (review S3-N3) and walks onboarding itself.
final class OnboardingAdversarial: XCTestCase {
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    static let headings = ["What are you training for?", "How many days a week?", "Your program"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor
    func test_freshInstall_opensOnStepOne_fullScreen_andNothingOfTodayIsSeenFirst() {
        let app = launch()
        let title = app.staticTexts["onboarding.title"]
        var seenFirst: Set<String> = []
        let deadline = Date().addingTimeInterval(15)
        while !title.exists, Date() < deadline { // as far as a UI test can see: one look per query
            if app.staticTexts["today.title"].exists {
                seenFirst.insert("Today's title")
            }
            if app.tabBars.firstMatch.exists {
                seenFirst.insert("a tab bar")
            }
        }
        XCTAssertEqual(seenFirst, [], "seen before onboarding")
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, Self.headings[0])
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertFalse(app.staticTexts["today.title"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["onboarding.progress"].label, "Step 1 of 3")
        XCTAssertEqual(selectedOptions(app), ["Both, honestly, Barbell strength + accessory volume"])
        XCTAssertFalse(app.buttons["onboarding.back"].exists, "step 1 has no Back")
        XCTAssertEqual(app.buttons["onboarding.cta"].label, "Continue")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(app.buttons["onboarding.skip"].frame.maxY, window.maxY - 120, "full screen")
        attach(app.screenshot(), named: "Fresh install")
    }

    @MainActor
    func test_eachStep_readsInTheTablesOrder_insideTheRealScrollView_atTheLargestTextSize() throws {
        let app = launch(Self.largestText)
        XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 15))
        try expectStops(Self.stepOne, in: app)
        continueTo(Self.headings[1], in: app)
        try expectStops(Self.stepTwo, in: app)
        continueTo(Self.headings[2], in: app)
        try expectStops(Self.stepThree, in: app)
        attach(app.screenshot(), named: "Step 3 at the largest text size")
    }

    @MainActor
    func test_aStepScrolledDown_isFollowedByAStepAtItsTop_atTheLargestTextSize() {
        let app = launch(Self.largestText)
        let title = app.staticTexts["onboarding.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        var tops = [title.frame.minY] // where each step's title stands when nothing was scrolled
        for heading in Self.headings.dropFirst() {
            continueTo(heading, in: app)
            tops.append(title.frame.minY)
        }
        for heading in Self.headings.dropLast().reversed() {
            app.buttons["onboarding.back"].tap()
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(title.frame.minY, tops[0], accuracy: 1)
        for (index, heading) in Self.headings.enumerated().dropFirst() {
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertLessThan(title.frame.minY, tops[index - 1] - 40, "step \(index) does not scroll at this size")
            continueTo(heading, in: app)
            XCTAssertEqual(title.frame.minY, tops[index], accuracy: 1, "\"\(heading)\" did not open at its top")
            XCTAssertTrue(app.buttons["onboarding.back"].isHittable, "Back is the top of \"\(heading)\"")
        }
    }

    @MainActor
    func test_picksSurviveBackAndForth_andStartTrainingSavesThem_landingOnToday() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 15))
        app.buttons["onboarding.option.0"].tap()
        XCTAssertEqual(selectedOptions(app), ["Get stronger, Low reps, linear load increases"])
        continueTo(Self.headings[1], in: app)
        XCTAssertEqual(selectedOptions(app), ["4 days, Upper / lower split"], "the default pick of step 2")
        XCTAssertTrue(app.buttons["onboarding.back"].isEnabled)
        app.buttons["onboarding.option.0"].tap()
        continueTo(Self.headings[2], in: app)
        XCTAssertTrue(app.staticTexts["Full Body, 8 weeks, pounds. Editable any time."].exists)
        XCTAssertEqual(previewRows(app), Self.fullBodyRows)
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts[Self.headings[1]].waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOptions(app), ["3 days, Full body each session"])
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOptions(app), ["Get stronger, Low reps, linear load increases"])
        XCTAssertFalse(app.buttons["onboarding.back"].exists)
        continueTo(Self.headings[1], in: app)
        continueTo(Self.headings[2], in: app)
        XCTAssertEqual(app.buttons["onboarding.cta"].label, "Start training")
        app.buttons["onboarding.cta"].tap()
        expectToday(app)
        attach(app.screenshot(), named: "Today after Start training")
        XCTAssertEqual(try storedRows(app), ["program": 1, "program_week": 8, "day_template": 3, "slot": 15])
    }

    @MainActor
    func test_skipSetup_fromEachStep_savesTheDefaultProgram_andLandsOnToday() throws {
        for step in 1 ... 3 {
            let app = launch()
            XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 15))
            for heading in Self.headings.dropFirst().prefix(step - 1) {
                app.buttons["onboarding.option.3"].tap() // "Stay consistent", then "6 days": not the default
                continueTo(heading, in: app)
            }
            app.buttons["onboarding.skip"].tap()
            expectToday(app)
            let rows = try storedRows(app)
            XCTAssertEqual(rows, ["program": 1, "program_week": 8, "day_template": 4, "slot": 16], "step \(step)")
            app.terminate()
        }
    }

    @MainActor
    func test_leavingTheAppMidOnboarding_keepsTheStepAndThePicks() {
        let app = launch()
        XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 15))
        app.buttons["onboarding.option.1"].tap()
        continueTo(Self.headings[1], in: app)
        app.buttons["onboarding.option.2"].tap()
        continueTo(Self.headings[2], in: app)
        let sentence = app.staticTexts["Push / Pull / Legs, 8 weeks, pounds. Editable any time."]
        XCTAssertTrue(sentence.exists)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(sentence.waitForExistence(timeout: 10), "step 3 and its picks did not survive leaving the app")
        XCTAssertFalse(app.staticTexts["today.title"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts[Self.headings[1]].waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOptions(app), ["5 days, Push, pull, legs + accessories"])
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts[Self.headings[0]].waitForExistence(timeout: 5))
        XCTAssertEqual(selectedOptions(app), ["Build muscle, Moderate reps, volume tracking"])
    }

    /// Light and dark. Three kinds of issue are excused, each on its own elements and for its own reason
    /// (`auditExclusions`); anything else the system reports fails the test.
    @MainActor
    func test_eachStep_passesTheSystemsAccessibilityAudit() throws {
        try auditEachStep(arguments: [], size: "the default text size")
    }

    @MainActor
    func test_eachStep_passesTheSystemsAccessibilityAudit_atTheLargestTextSize() throws {
        try auditEachStep(arguments: Self.largestText, size: "the largest text size")
    }
}

extension OnboardingAdversarial {
    @MainActor
    func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.fresh(arguments)
        app.launch()
        return app
    }

    /// Taps the pinned primary button and waits for the step whose title is `heading`.
    @MainActor
    func continueTo(_ heading: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["onboarding.cta"].tap()
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5), heading, file: file, line: line)
    }

    @MainActor
    func selectedOptions(_ app: XCUIApplication) -> [String] {
        (0 ... 3).map { app.buttons["onboarding.option.\($0)"] }.filter(\.isSelected).map(\.label)
    }

    @MainActor
    func previewRows(_ app: XCUIApplication) -> [String] {
        let rows = NSPredicate(format: "identifier BEGINSWITH 'onboarding.preview.'")
        return app.descendants(matching: .any).matching(rows).allElementsBoundByIndex.map(\.label)
    }

    /// The step's stops in the order of the app's accessibility tree, which is VoiceOver's: every button, every
    /// text and every element onboarding names, each taken whole.
    @MainActor
    func expectStops(
        _ expected: [AdversarialStop],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var read: [AdversarialStop] = []
        func walk(_ node: any XCUIElementSnapshot) {
            let isStop = node.elementType == .button || node.elementType == .staticText
                || node.identifier.hasPrefix("onboarding.")
            guard isStop, !node.label.isEmpty else {
                node.children.forEach(walk)
                return
            }
            let isButton = node.elementType == .button
            read.append(AdversarialStop(
                label: node.label,
                isButton: isButton,
                isSelected: node.isSelected,
                isEnabled: node.isEnabled
            ))
        }
        try walk(app.snapshot())
        XCTAssertEqual(read.map(\.description), expected.map(\.description), file: file, line: line)
    }

    /// Today, with the tab bar, and nothing of onboarding.
    @MainActor
    func expectToday(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(app.tabBars.buttons.count, 4, file: file, line: line)
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected, file: file, line: line)
        XCTAssertFalse(app.staticTexts["onboarding.title"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, file: file, line: line)
    }

    /// Criterion 7: the debug menu opens from a long press on Today's title; its Diagnostics page says how many
    /// rows the program onboarding saved has.
    @MainActor
    func storedRows(_ app: XCUIApplication) throws -> [String: Int] {
        app.staticTexts["today.title"].press(forDuration: 1)
        let diagnostics = app.buttons["debug.menu.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5), "the debug menu did not open from Today's title")
        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["debug.diagnostics.rows.program"].waitForExistence(timeout: 10))
        var rows: [String: Int] = [:]
        for table in ["program", "program_week", "day_template", "slot"] {
            rows[table] = try XCTUnwrap(Int(app.staticTexts["debug.diagnostics.rows.\(table)"].label), table)
        }
        return rows
    }

    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
