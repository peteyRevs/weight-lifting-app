import XCTest

/// F15 S2a: each audited screen's exclusions excuse what they name and nothing wider, as
/// `OnboardingAdversarial.test_auditExclusions_excuseNothingWider` holds onboarding's. No app is launched: the
/// issues are made here, one excused as measured and its near misses beside it (the same issue on another element
/// or screen, another issue on the same element, a frame that is not where the exclusion says).
final class AuditExclusionsTests: XCTestCase {
    /// The system's words for the issues, as the runs reported them.
    static let clipped = "Text clipped"
    static let contrast = "Contrast failed"
    static let nearly = "Contrast nearly passed"
    static let dynamicType = "Dynamic Type font sizes are partially unsupported"
    static let hitArea = "Hit area is too small"
    /// The tab bar and pinned parts where the runs measured them, on the iPhone 17 (402 × 874 pt).
    static let tabBar = CGRect(x: 20, y: 791, width: 362, height: 63)
    static let panel = CGRect(x: 0, y: 661, width: 402, height: 213)
    static let sheetButton = CGRect(x: 0, y: 746, width: 402, height: 128)

    static func issue(
        _ screen: String, _ summary: String, _ label: String, type: XCUIElement.ElementType = .staticText,
        identifier: String = "", frame: CGRect = CGRect(x: 26, y: 300, width: 200, height: 12),
        pinned: CGRect = .null, way: AuditWay = .light
    ) -> ScreenIssue {
        let auditType: XCUIAccessibilityAuditType = switch summary {
        case clipped: .textClipped
        case hitArea: .hitRegion
        case dynamicType: .dynamicType
        default: .contrast
        }
        return ScreenIssue(
            way: way, screen: screen, type: auditType, summary: summary, elementType: type,
            identifier: identifier, label: label, frame: frame, tabBar: tabBar, pinned: pinned
        )
    }

    /// Asserts that `excused` are all excused by `exclusions`, and that none of `nearMisses` is.
    private func check(_ exclusions: [ScreenExclusion], excused: [ScreenIssue], nearMisses: [ScreenIssue]) {
        let notExcused = excused.filter { ScreenAudit.exclusion(for: $0, in: exclusions) == nil }
        XCTAssertEqual(notExcused.map(\.description), [], "not excused, and should be")
        let wider = nearMisses.filter { ScreenAudit.exclusion(for: $0, in: exclusions) != nil }
        XCTAssertEqual(wider.map(\.description), [], "excused, and should not be")
    }

    @MainActor
    func test_workoutExclusions_excuseNothingWider() {
        let under = CGRect(x: 26, y: 702, width: 7, height: 12)
        let above = CGRect(x: 26, y: 600, width: 7, height: 12)
        let minimize = "workout.header.minimize"
        check(AuditWorkout.exclusions, excused: [
            Self.issue("solo card", Self.dynamicType, "REMAINING"),
            Self.issue("solo card", Self.clipped, "Minimize", type: .button, identifier: minimize),
            Self.issue("rest panel", Self.contrast, "5", frame: under, pinned: Self.panel),
            Self.issue("rest panel", Self.contrast, "+ Add set", type: .button, frame: under, pinned: Self.panel),
            Self.issue("finish sheet", Self.nearly, "Save workout", type: .button),
            Self.issue("receipt", Self.hitArea, "Friday, November 13")
        ], nearMisses: [
            Self.issue("solo card", Self.dynamicType, "Barbell Bench Press"),
            Self.issue("solo card", Self.clipped, "Finish", type: .button),
            Self.issue("solo card", Self.contrast, "Minimize", type: .button),
            Self.issue("Settings", Self.clipped, "Minimize", type: .button, identifier: minimize),
            Self.issue("solo card", Self.clipped, "Minimize", type: .button, identifier: minimize, way: .largest),
            // A line above the panel's top, a line over a screen with no panel, and what is no text or button.
            Self.issue("rest panel", Self.contrast, "5", frame: above, pinned: Self.panel),
            Self.issue("solo card", Self.contrast, "5", frame: under),
            Self.issue("rest panel", Self.contrast, "B", type: .other, frame: under, pinned: Self.panel),
            Self.issue("finish sheet", Self.contrast, "Save workout", type: .button),
            Self.issue("finish sheet", Self.nearly, "Discard", type: .button),
            Self.issue("receipt", Self.hitArea, "Done", type: .button),
            Self.issue("solo card", Self.hitArea, "Elapsed time", type: .other),
            Self.issue("receipt", Self.clipped, "Friday, November 13")
        ])
    }

    @MainActor
    func test_programAndLibraryExclusions_excuseNothingWider() {
        let underBar = CGRect(x: 58, y: 765, width: 210, height: 104)
        let underButton = CGRect(x: 24, y: 753, width: 156, height: 18)
        let name = "library.create.name"
        check(AuditProgramLibrary.exclusions, excused: [
            Self.issue("Day editor", Self.dynamicType, "DAY 2 OF 4"),
            Self.issue("Day editor", Self.clipped, "Day name", type: .textField),
            Self.issue("Day editor", Self.contrast, "Romanian Deadlift", frame: underBar),
            Self.issue(
                "exercise picker",
                Self.contrast,
                "Band External Rotation",
                frame: underButton,
                pinned: Self.sheetButton
            ),
            Self.issue("New exercise", Self.nearly, "Save", type: .button),
            Self.issue("Edit exercise", Self.clipped, "", type: .textField, identifier: name)
        ], nearMisses: [
            Self.issue("Edit exercise", Self.clipped, "", type: .textField, identifier: name, way: .largest),
            Self.issue("New exercise", Self.contrast, "", type: .textField, identifier: name),
            Self.issue("Day editor", Self.clipped, "Lower A — Squat focus"),
            Self.issue("Day editor", Self.contrast, "Romanian Deadlift"),
            Self.issue("Day editor", Self.contrast, "Program", type: .button, frame: underBar),
            Self.issue("exercise picker", Self.contrast, "Band External Rotation", frame: underBar),
            Self.issue("exercise picker", Self.contrast, "Arnold Press", pinned: Self.sheetButton),
            Self.issue("New exercise", Self.contrast, "Save", type: .button),
            Self.issue("Day editor", Self.nearly, "Save", type: .button)
        ])
    }

    @MainActor
    func test_historyAndSettingsExclusions_excuseNothingWider() {
        let underBar = CGRect(x: 26, y: 774, width: 79, height: 44)
        let edit = CGRect(x: 328, y: 66, width: 53, height: 36)
        let editID = "history.workout.edit"
        let low = CGRect(x: 24, y: 761, width: 12, height: 24)
        let high = CGRect(x: 24, y: 600, width: 12, height: 24)
        check(AuditHistorySettings.exclusions, excused: [
            Self.issue("workout detail", Self.dynamicType, "LB MOVED"),
            Self.issue("workout detail", Self.clipped, "8 new PRs this session"),
            Self.issue("workout detail", Self.contrast, "Delete workout", type: .button, frame: underBar),
            Self.issue("Settings", Self.contrast, "Apple Health", frame: underBar),
            Self.issue("workout detail", Self.contrast, "Edit", type: .button, identifier: editID, frame: edit),
            Self.issue("edit sets", Self.contrast, "5", frame: low, pinned: Self.sheetButton)
        ], nearMisses: [
            Self.issue("workout detail", Self.contrast, "Delete workout", type: .button),
            Self.issue("workout detail", Self.contrast, "History", type: .button, frame: underBar),
            Self.issue("Bar and plates", Self.contrast, "Apple Health", frame: underBar),
            Self.issue("workout detail", Self.clipped, "Edit", type: .button, identifier: editID),
            Self.issue("workout detail", Self.contrast, "Edit", type: .button, frame: edit),
            Self.issue("edit sets", Self.contrast, "5", frame: high, pinned: Self.sheetButton),
            Self.issue("workout detail", Self.dynamicType, "Upper A — Push focus"),
            // F15-S2-12 is an open finding, never an exclusion.
            ScreenIssue(screen: "Settings", type: .textClipped, summary: "Potentially inaccessible text")
        ])
    }
}
