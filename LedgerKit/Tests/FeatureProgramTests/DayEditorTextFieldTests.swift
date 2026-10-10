#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDomain
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, criteria 4 and 10: the day's name, read through UIKit as `ProgramTextFieldTests` reads the
    /// program's. In a package test process a text field is no accessibility element, so the hosted reader
    /// does not see it and the pinned trees do not hold it; here it is found as the `UITextField` it is, with
    /// its placeholder, which is its spoken label too, and its text, and its draft follows `ProgramHeader`'s
    /// rule.
    ///
    /// **Not covered by any hosted test:** typing. A hosted field takes no text from a test, so that a typed
    /// name is sent as `rename` with the day's id, and that VoiceOver reads the field as "Day name", wait
    /// for the UI tests of S14. That the view spells exactly that action is pinned from its source
    /// (`ProgramViewsSourceAdversarialTests.views_sendOnlyTheModelsActions`).
    @Suite("Day editor name field", .serialized, .tags(.feature))
    struct DayEditorTextFieldTests {
        typealias Hosted = ProgramTextFieldTests.Hosted

        /// Upper A's editor, the day stored under `name`.
        static func content(named name: String) throws -> DayEditorModel.Content {
            var input = try DayEditorFixtures.seedInput()
            input.program = ProgramEditing.renameDay(input.program, day: input.day, to: name)
            return try DayEditorPresentation.make(input).content()
        }

        @Test("The Day editor's one field holds the day's name over the placeholder Day name, open or closed")
        func nameField_holdsTheName() {
            let name = "Upper A — Push focus"
            #expect(ProgramTextFieldTests.fields(of: .dayEditor) == [["Day name", name]])
            #expect(ProgramTextFieldTests.fields(of: .dayOpenLinear) == [["Day name", name]], "a stepper is no field")
            #expect(ProgramTextFieldTests.fields(of: .dayLongNames) == [["Day name", ProgramPreviewData.longDayName]])
        }

        @Test("The name field follows the stored name while it has no focus, and sends nothing for it")
        func nameField_withoutFocus_followsTheStoredName() throws {
            var sent: [DayEditorAction] = []
            let hosted = try Hosted(DayEditorHeader(model: Self.content(named: "Upper A")) { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            #expect(field.text == "Upper A")
            try hosted.show(DayEditorHeader(model: Self.content(named: "Arms")) { sent.append($0) })
            #expect(field.text == "Arms")
            #expect(sent.isEmpty, "a name that came from the store is not sent back to it")
        }

        @Test("While the name field has focus it keeps its draft; when it loses focus it takes the stored name")
        func nameField_withFocus_keepsItsDraft() throws {
            var sent: [DayEditorAction] = []
            let hosted = try Hosted(DayEditorHeader(model: Self.content(named: "Upper A")) { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            try #require(field.becomeFirstResponder(), "the hosted field takes no focus")
            hosted.settle()
            try hosted.show(DayEditorHeader(model: Self.content(named: "Upper A, cleaned")) { sent.append($0) })
            #expect(field.text == "Upper A", "the stored name is not written into a field being edited")
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(field.text == "Upper A, cleaned")
            #expect(sent.isEmpty)
        }

        /// The limit `ProgramTextFieldTests.fields_areNotReadByTheHostedReader` keeps known, here for the
        /// day's name: when the reader learns to read a field this fails, and the field goes into
        /// `DayEditorTrees`.
        @Test("Limit: the hosted reader reads the header's four stops and not the name field")
        func nameField_isNotReadByTheHostedReader() throws {
            let model = try ProgramPreview.dayEditor.dayEditorModel()
            let stops = DayEditorHeader(model: model) { _ in }.stops()
            #expect(stops == DayEditorTrees.header("DAY 1 OF 4", meta: "Week 1 · 5 exercises · 18 sets · ~39 min"))
            #expect(!stops.contains { $0.kind == .field })
        }
    }
#endif
