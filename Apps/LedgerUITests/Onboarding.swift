import XCTest

/// F08 S3 criterion 8: onboarding in the running app, on a fresh database. The lifter's walk through the three
/// steps to a saved program and Today; and, at an accessibility text size, what only the running app shows:
/// VoiceOver's stops in order inside the real scroll view, taps on the page's controls, and each step opening
/// at its top. It is the screen's one reader of the real scroll view (docs/testing-strategy.md §2.6: the
/// package tests read the page and the pinned part without it). Nightly only, as every UI test but `Smoke` is.
final class Onboarding: XCTestCase {
    /// The largest text size of the snapshot matrix (AX3): every step is longer than the screen there.
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_threeStepsGenerateProgram() throws {
        let app = launch()
        XCTAssertFalse(app.tabBars.firstMatch.exists, "onboarding is full screen: no tab bar")
        XCTAssertEqual(picks(in: app), [false, false, true, false], "Both, honestly")
        app.buttons["onboarding.option.0"].tap()
        XCTAssertEqual(picks(in: app), [true, false, false, false], "Get stronger, and no other")

        app.buttons["onboarding.cta"].tap()
        waitForTitle("How many days a week?", in: app)
        XCTAssertEqual(picks(in: app), [false, true, false, false], "4 days")
        app.buttons["onboarding.option.0"].tap()
        XCTAssertEqual(picks(in: app), [true, false, false, false], "3 days, and no other")

        app.buttons["onboarding.back"].tap()
        waitForTitle("What are you training for?", in: app)
        XCTAssertEqual(picks(in: app), [true, false, false, false], "the goal survives going back")
        app.buttons["onboarding.cta"].tap()
        waitForTitle("How many days a week?", in: app)
        XCTAssertEqual(picks(in: app), [true, false, false, false], "the days survive going forth")

        app.buttons["onboarding.cta"].tap()
        waitForTitle("Your program", in: app)
        XCTAssertTrue(app.staticTexts["Full Body, 8 weeks, pounds. Editable any time."].exists)
        let days = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding.preview.'"))
        XCTAssertEqual(days.allElementsBoundByIndex.map(\.label), [
            "Full Body A · Squat focus, Squat, bench, pulldown, laterals, curl",
            "Full Body B · Bench focus, Bench, RDL, row, leg press, pushdown",
            "Full Body C · Deadlift focus, Deadlift, OHP, pull-up, leg curl, rear delt"
        ])
        XCTAssertEqual(app.buttons["onboarding.cta"].label, "Start training")
        attachScreenshot(of: app, named: "Step 3")

        app.buttons["onboarding.cta"].tap()
        try expectTodayWithTheProgram(in: app)
    }

    /// "Start training" landed on Today with the tabs, and the database holds the program the picks asked for:
    /// one program of eight weeks, the three days of the full-body split and their fifteen slots.
    @MainActor
    private func expectTodayWithTheProgram(in app: XCUIApplication) throws {
        let today = app.staticTexts["today.title"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(app.staticTexts["onboarding.title"].exists)
        attachScreenshot(of: app, named: "Today")

        today.press(forDuration: 1)
        let diagnostics = app.buttons["debug.menu.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let programs = app.staticTexts["debug.diagnostics.rows.program"]
        XCTAssertTrue(programs.waitForExistence(timeout: 10))
        let rows = ["program", "program_week", "day_template", "slot"].map {
            app.staticTexts["debug.diagnostics.rows.\($0)"].label
        }
        XCTAssertEqual(rows, ["1", "8", "3", "15"])
    }

    @MainActor
    func test_voiceOverReadsEachStepInOrder_insideTheScrollView_atAnAccessibilitySize() throws {
        let app = launch(Self.largeText)
        XCTAssertEqual(try stops(in: app, named: "Step 1"), Self.goalStep(picked: 2))

        // A tap on a control of the page, inside the scroll view, reaches the store: the pick moves.
        app.buttons["onboarding.option.3"].tap()
        XCTAssertEqual(try stops(in: app, named: "Step 1, Stay consistent"), Self.goalStep(picked: 3))

        app.buttons["onboarding.cta"].tap()
        waitForTitle("How many days a week?", in: app)
        XCTAssertEqual(try stops(in: app, named: "Step 2"), Self.daysStep)

        app.buttons["onboarding.cta"].tap()
        waitForTitle("Your program", in: app)
        XCTAssertEqual(try stops(in: app, named: "Step 3"), Self.programStep)
    }

    @MainActor
    func test_eachStepOpensAtItsTop_atAnAccessibilitySize() {
        let app = launch(Self.largeText)
        XCTAssertEqual(app.scrollViews.count, 1)
        let title = app.staticTexts["onboarding.title"]
        let bars = app.otherElements["onboarding.progress"]
        // A step that has just opened: where the launch left step 1. The bars and the title start at the same
        // height on every step ("Back" keeps its place on step 1).
        let atTheTop = (title: title.frame.minY, bars: bars.frame.minY)

        for next in ["How many days a week?", "Your program"] {
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertLessThan(title.frame.minY, atTheTop.title - 100, "control: the step is longer than the screen")
            app.buttons["onboarding.cta"].tap()
            waitForTitle(next, in: app)
            XCTAssertEqual(title.frame.minY, atTheTop.title, accuracy: 1, "\(next) opens at its top")
            XCTAssertEqual(bars.frame.minY, atTheTop.bars, accuracy: 1, "\(next) opens at its top")
            XCTAssertTrue(app.buttons["onboarding.back"].isHittable, "\(next): Back, its first stop, is in reach")
            attachScreenshot(of: app, named: next)
        }
    }
}

// MARK: - The intended stops (the tables of F08's implementation notes, "The intended VoiceOver trees")

/// One stop of VoiceOver as XCUITest, a real accessibility client, reads it from the running app.
private struct Stop: Equatable, CustomStringConvertible {
    enum Kind: String {
        case button, text, element
    }

    var label: String
    var kind = Kind.button
    var isSelected = false
    var isEnabled = true

    var description: String {
        "\(kind.rawValue) \"\(label)\"\(isSelected ? " selected" : "")\(isEnabled ? "" : " not enabled")"
    }
}

private extension Onboarding {
    static func goalStep(picked: Int) -> [Stop] {
        let options = [
            "Get stronger, Low reps, linear load increases",
            "Build muscle, Moderate reps, volume tracking",
            "Both, honestly, Barbell strength + accessory volume",
            "Stay consistent, Habit first, numbers second"
        ]
        return [
            Stop(label: "Step 1 of 3", kind: .element),
            Stop(label: "What are you training for?", kind: .text),
            Stop(label: "This sets how your loads progress week to week.", kind: .text)
        ] + options.enumerated().map { Stop(label: $1, isSelected: $0 == picked) } + [
            Stop(label: "Continue"),
            Stop(label: "Skip setup")
        ]
    }

    static let daysStep = [
        Stop(label: "Back"),
        Stop(label: "Step 2 of 3", kind: .element),
        Stop(label: "How many days a week?", kind: .text),
        Stop(label: "Pick the number you will actually hit, not the one you want to hit.", kind: .text),
        Stop(label: "3 days, Full body each session"),
        Stop(label: "4 days, Upper / lower split", isSelected: true),
        Stop(label: "5 days, Push, pull, legs + accessories"),
        Stop(label: "6 days, Body-part split"),
        Stop(label: "Continue"),
        Stop(label: "Skip setup")
    ]

    static let programStep = [
        Stop(label: "Back"),
        Stop(label: "Step 3 of 3", kind: .element),
        Stop(label: "Your program", kind: .text),
        Stop(label: "Upper / Lower, 8 weeks, pounds. Editable any time.", kind: .text),
        Stop(label: "Upper A · Push focus, Bench, incline, row, pulldown, laterals", kind: .text),
        Stop(label: "Lower A · Squat focus, Squat, RDL, leg press, calves", kind: .text),
        Stop(label: "Upper B · Pull focus, Weighted pull-up, OHP, row, curls", kind: .text),
        Stop(label: "Lower B · Hinge focus, Deadlift, front squat, leg curl", kind: .text),
        Stop(label: "Start training"),
        Stop(label: "Skip setup")
    ]
}

// MARK: - Reading the running app

private extension Onboarding {
    /// The app on onboarding's first step, launched on a fresh database with `arguments`.
    @MainActor
    func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.fresh(arguments)
        app.launch()
        waitForTitle("What are you training for?", in: app, timeout: 10)
        return app
    }

    /// Waits for the step whose title is `text`: every step's title carries the same identifier.
    @MainActor
    func waitForTitle(
        _ text: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let title = app.staticTexts.matching(identifier: "onboarding.title")
            .matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), text, file: file, line: line)
    }

    /// Which of the step's four options are selected, in order.
    @MainActor
    func picks(in app: XCUIApplication) -> [Bool] {
        (0 ..< 4).map { app.buttons["onboarding.option.\($0)"].isSelected }
    }

    /// VoiceOver's stops in the order of the app's accessibility tree, the page inside its scroll view first,
    /// then the pinned buttons: every button and text, and any other element that has a label and nothing
    /// under it (the bars; the scroll view's own scroll bar holds its thumb, and is no stop of the screen's).
    /// A button is one stop, whatever texts it holds. The stops as read are attached under `name`.
    @MainActor
    func stops(in app: XCUIApplication, named name: String) throws -> [Stop] {
        let found = try Self.stops(under: app.snapshot())
        let attachment = XCTAttachment(string: found.map(\.description).joined(separator: "\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return found
    }

    static func stops(under node: any XCUIElementSnapshot) -> [Stop] {
        let kind: Stop.Kind? = switch node.elementType {
        case .button: .button
        case .staticText: .text
        default: node.label.isEmpty || !node.children.isEmpty ? nil : .element
        }
        if let kind {
            return [Stop(label: node.label, kind: kind, isSelected: node.isSelected, isEnabled: node.isEnabled)]
        }
        return node.children.flatMap { stops(under: $0) }
    }

    /// Kept with the result, so a run shows the screens it checked.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
