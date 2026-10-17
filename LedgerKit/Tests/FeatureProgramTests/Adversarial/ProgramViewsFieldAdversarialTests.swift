#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, gate G2, round 1: the two text fields, as far as a hosted test reaches them. Typing does not
    /// reach SwiftUI from a hosted `UITextField` (tried here: `insertText` with focus, the text set and
    /// `.editingChanged` sent, the text-did-change notification; the field's own text changes and the view's
    /// draft does not), so what the name field sends for a typed name stays with the UI tests of S13. What a
    /// hosted test can hold a field to is what it must not send: an action for a focus, a blur, or a name that
    /// came from the store.
    @Suite("Adversarial F11 S9 · the two text fields", .serialized, .tags(.feature))
    struct ProgramViewsFieldAdversarialTests {
        typealias Hosted = ProgramTextFieldTests.Hosted

        static func header(_ name: String, sent: @escaping (ProgramBuilderAction) -> Void) -> ProgramHeader {
            ProgramHeader(
                model: ProgramBuilderModel.Header(eyebrow: "MY PROGRAM", name: name, namePlaceholder: "Program name"),
                send: sent
            )
        }

        @Test(
            "The name field sends nothing for a focus, a blur, or a stored name that changes under either",
            arguments: ["Upper / Lower", "", "  two  spaces  ", BuilderState.longName]
        )
        func nameField_focusAndBlur_sendNothing(_ name: String) throws {
            var sent: [ProgramBuilderAction] = []
            let hosted = Hosted(Self.header(name) { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            #expect(field.text == name, "the field shows the stored name as it is stored")
            try #require(field.becomeFirstResponder())
            hosted.settle()
            hosted.show(Self.header(name + " B") { sent.append($0) })
            #expect(field.text == name, "a field being edited keeps its draft")
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(field.text == name + " B")
            hosted.show(Self.header("") { sent.append($0) })
            #expect(field.text?.isEmpty == true, "a stored name that is empty empties the field")
            #expect(sent.isEmpty, "\(sent.count) actions")
        }

        /// **FINDING F11-S9-3** (minor, and a question for S14). The search field's binding writes the query
        /// back when the field takes the focus and when it loses it: `.setQuery("sq")` is sent twice for each,
        /// with the query unchanged (hosted, iOS 27.0; whether a device does the same is for the UI tests). The
        /// action is one that may be applied twice, so nothing breaks by itself; but a blur is also how the
        /// keyboard goes away when the sheet closes, and S14's store empties the query on closing: a
        /// `.setQuery` of the old text that arrives after it would bring the query back. The name field
        /// already guards its own send (`text != model.name`); the same guard here is one line.
        @Test("The search field sends nothing when it takes the focus or loses it")
        func searchField_focusAndBlur_sendNothing() throws {
            var sent: [ExercisePickerAction] = []
            let model = ExercisePickerModel.Search(placeholder: "Search exercises", query: "sq")
            let hosted = Hosted(ExerciseSearchField(model: model) { sent.append($0) })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            try #require(field.becomeFirstResponder())
            hosted.settle()
            #expect(sent.isEmpty, "focus sent \(sent)")
            #expect(field.resignFirstResponder())
            hosted.settle()
            #expect(sent.isEmpty, "blur sent \(sent)")
            #expect(field.text == "sq")
        }

        @Test("The search field shows the model's query, a long one too, and never a draft of its own")
        func searchField_followsTheModel() throws {
            let placeholder = "Search exercises"
            let hosted = Hosted(ExerciseSearchField(model: .init(placeholder: placeholder, query: "row")) { _ in })
            defer { hosted.close() }
            let field = try #require(hosted.fields.first)
            #expect(field.text == "row" && field.placeholder == placeholder)
            try #require(field.becomeFirstResponder())
            hosted.settle()
            hosted
                .show(ExerciseSearchField(model: .init(placeholder: placeholder, query: LibraryState.queryText)) { _ in
                })
            #expect(field.text == LibraryState.queryText, "the store's query is shown while the field has focus")
            hosted.show(ExerciseSearchField(model: .init(placeholder: placeholder, query: "")) { _ in })
            #expect(field.text?.isEmpty == true, "closing the sheet empties the query")
        }
    }
#endif
