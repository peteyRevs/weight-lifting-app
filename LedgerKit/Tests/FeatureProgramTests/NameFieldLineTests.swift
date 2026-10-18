#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// The chore of 2026-10-13 (`tasks/chores/2026-10-13-name-field-line-height.md`): the name field is set
    /// with `ledgerFieldFont`, and the builder's `ProgramHeader` holds a `NameField` as the Day editor's
    /// header does. Measured as the tester of F11 S10 measures the day's name: the letters' box at 3×, in a
    /// hosted window, without the focus and with it.
    ///
    /// **Not covered by any hosted test:** typing, and a finger's tap (`ProgramTextFieldTests`).
    @Suite("Name field line", .serialized, .tags(.feature))
    struct NameFieldLineTests {
        typealias Shown = DayEditorViewsNameAdversarialTests.Shown

        /// The two places a name is edited: the Day editor's field by itself, and the builder's header
        /// without its eyebrow, so that the only ink is the name's.
        enum Place: String, CaseIterable {
            case day, program

            func view(_ name: String) -> AnyView {
                switch self {
                case .day:
                    AnyView(NameField(label: "Day name", name: name) { _ in })
                case .program:
                    AnyView(ProgramHeader(model: Self.header(name, eyebrow: "")) { _ in })
                }
            }

            static func header(_ name: String, eyebrow: String = "MY PROGRAM") -> ProgramBuilderModel.Header {
                ProgramBuilderModel.Header(eyebrow: eyebrow, name: name, namePlaceholder: "Program name")
            }
        }

        /// The five letters with a tail. Their box without the focus is the wrapping text's, which nothing
        /// clips; with the focus it is the field's.
        @Test(
            "With the focus both names keep their tails and their place, at every text size, plain and bold",
            arguments: DynamicTypeSize.allCases
        )
        func focus_keepsTheTails(_ size: DynamicTypeSize) throws {
            for place in Place.allCases {
                for weight in [LegibilityWeight.regular, .bold] {
                    let shown = try Shown(
                        hosting: place.view("gjpqy").environment(\.legibilityWeight, weight),
                        at: size
                    )
                    defer { shown.close() }
                    let whole = try shown.letters()
                    try shown.focus(true)
                    let focused = try shown.letters()
                    let text = "\(place) \(size) \(weight): \(whole), with the focus \(focused)"
                    // A pixel of the drawing at 3× is a third of a point.
                    #expect(focused.height > whole.height - 0.34, "the tails are cut: \(text)")
                    #expect(abs(focused.minY - whole.minY) < 2 && abs(focused.minX - whole.minX) < 0.34, "\(text)")
                }
            }
        }

        @Test("A long program name wraps without the focus, is one line with it, and wraps again after", arguments: [
            DynamicTypeSize.large, .accessibility3
        ])
        func longProgramName_wrapsUnlessEdited(_ size: DynamicTypeSize) throws {
            let line = LedgerFont.scaledSize(.title, dynamicTypeSize: size)
            let shown = try Shown(hosting: Place.program.view(ProgramPreviewData.longName), at: size)
            defer { shown.close() }
            let before = try shown.letters()
            #expect(before.height > 2 * line && before.width <= 323.5, "\(before): not on three lines or more")
            try shown.focus(true)
            let with = try shown.letters()
            #expect(with.height < 1.1 * line && with.width > 280, "\(with): not one line that fills the field")
            #expect(abs(with.minY - before.minY) < 2, "the first line moves: \(before), then \(with)")
            try shown.focus(false)
            #expect(try shown.letters() == before)
        }

        /// What VoiceOver is given is what it was given before the header took `NameField`: the eyebrow as a
        /// heading, and the field, which the hosted reader does not read
        /// (`ProgramTextFieldTests.fields_areNotReadByTheHostedReader`) and which is found here as the
        /// `UITextField` it is. The name drawn as text under the field is hidden from VoiceOver. The whole
        /// builder's trees are `ProgramAccessibilityTests`', which pass unedited.
        @Test("The builder's header reads its heading and its one field, and never the drawn name", arguments: [
            "Upper / Lower", ProgramPreviewData.longName
        ])
        func programHeader_voiceOver_isTheHeadingAndTheField(_ name: String) {
            let header = ProgramHeader(model: Place.header(name)) { _ in }
            let stops = header.stops()
            #expect(stops == [.heading("MY PROGRAM")], "\(stops)")
            let hosted = ProgramTextFieldTests.Hosted(header)
            defer { hosted.close() }
            #expect(hosted.fields.map { [$0.placeholder ?? "", $0.text ?? ""] } == [["Program name", name]])
        }
    }
#endif
