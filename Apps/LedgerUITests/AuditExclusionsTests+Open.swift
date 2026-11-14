import XCTest

extension AuditExclusionsTests {
    /// The open findings (F15-S2-10 to 12) are expected failures of what they name only: the same issue in another
    /// way, on another element or screen, or (for the element-less one) in another number, is no open finding and
    /// fails as any other issue does.
    @MainActor
    func test_openFindings_nameOnlyTheirIssue() {
        let minimize = Self.issue(
            "solo card",
            Self.clipped,
            "Minimize",
            type: .button,
            identifier: "workout.header.minimize",
            way: .largest
        )
        let name = Self.issue(
            "Edit exercise",
            Self.clipped,
            "",
            type: .textField,
            identifier: "library.create.name",
            way: .largest
        )
        XCTAssertTrue(AuditWorkout.headerPillsBroken.names(minimize, among: [minimize]))
        XCTAssertTrue(AuditProgramLibrary.truncatedName.names(name, among: [name]))
        var elsewhere = minimize
        elsewhere.way = .light
        XCTAssertFalse(AuditWorkout.headerPillsBroken.names(elsewhere, among: [elsewhere]), "at the default size")
        elsewhere = name
        elsewhere.identifier = "workout.header.finish"
        XCTAssertFalse(AuditProgramLibrary.truncatedName.names(elsewhere, among: [elsewhere]), "another element")
        elsewhere = name
        elsewhere.summary = Self.contrast
        XCTAssertFalse(AuditProgramLibrary.truncatedName.names(elsewhere, among: [elsewhere]), "another issue")
        let field = Self.issue("Day editor", Self.contrast, "Day name", type: .textField, way: .dark)
        XCTAssertTrue(AuditProgramLibrary.hiddenFieldText.names(field, among: [field]))
        elsewhere = field
        elsewhere.way = .light
        XCTAssertFalse(AuditProgramLibrary.hiddenFieldText.names(elsewhere, among: [elsewhere]), "in light")
        elsewhere = field
        elsewhere.label = "Program name"
        XCTAssertFalse(AuditProgramLibrary.hiddenFieldText.names(elsewhere, among: [elsewhere]), "another field")
    }

    /// F15-S2-12 names exactly two element-less issues on Settings in one way, at the default size.
    @MainActor
    func test_openElementlessFinding_namesExactlyTwoOnSettings() {
        let open = AuditHistorySettings.unlabelledText
        let unlabelled = ScreenIssue(
            screen: "Settings",
            type: .elementDetection,
            summary: "Potentially inaccessible text"
        )
        XCTAssertTrue(open.names(unlabelled, among: [unlabelled, unlabelled]))
        XCTAssertFalse(open.names(unlabelled, among: [unlabelled, unlabelled, unlabelled]), "a third")
        XCTAssertFalse(open.names(unlabelled, among: [unlabelled]), "one alone")
        var dark = unlabelled
        dark.way = .dark
        XCTAssertFalse(open.names(unlabelled, among: [unlabelled, dark]), "two, but in two ways")
        var drawn = unlabelled
        drawn.screen = "Bar and plates"
        XCTAssertFalse(open.names(drawn, among: [drawn, drawn]), "another screen")
        drawn = unlabelled
        drawn.frame = CGRect(x: 26, y: 300, width: 40, height: 15)
        XCTAssertFalse(open.names(drawn, among: [drawn, drawn]), "an element with a frame")
        drawn = unlabelled
        drawn.type = .contrast
        XCTAssertFalse(open.names(drawn, among: [drawn, drawn]), "another type of issue")
        drawn = unlabelled
        drawn.way = .largest
        XCTAssertFalse(open.names(drawn, among: [drawn, drawn]), "at Accessibility XXXL")
    }
}
