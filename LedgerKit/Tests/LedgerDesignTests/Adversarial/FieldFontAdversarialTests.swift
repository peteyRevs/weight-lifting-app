#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// The chore of 2026-10-13, gate G2: `ledgerFieldFont(_:)` on the roles the implementer did not
        /// measure. Its doc comment promises two things of every role: the tails are whole while the field
        /// is edited, and "a field laid top on top over such a text draws its letters where the text draws
        /// them". Measured as `FieldFontTests` measures the title: "Gyp" as a text of the role and as an
        /// edited field of the role over it, white on black at 3×.
        @Suite("FieldFont (adversarial, chore 2026-10-13)", .tags(.design))
        struct FieldFontAdversarialTests {
            /// The phone's roles but the eyebrow, whose capitals have no tail.
            nonisolated static let roles: [LedgerFont.Role] = [
                .display, .title, .heading, .subheading, .body, .bodyLight, .label, .caption, .button,
                .numeralXL, .numeralL, .numeralM, .numeralS
            ]

            /// The ink of "Gyp" as a text of `role`, and as an edited field of the role over that text.
            static func inks(
                _ role: LedgerFont.Role,
                at size: DynamicTypeSize
            ) throws -> (text: CGRect, field: CGRect) {
                func pair(drawsField: Bool) -> some View {
                    FieldFontTests.pair(role, drawsField: drawsField) { $0.ledgerFieldFont(role) }
                }
                return try (
                    FieldFontTests.ink(pair(drawsField: false), at: size, isEdited: false),
                    FieldFontTests.ink(pair(drawsField: true), at: size, isEdited: true)
                )
            }

            @Test("An edited field of every role draws its tails whole", arguments: roles)
            func everyRole_edited_drawsItsTailsWhole(_ role: LedgerFont.Role) throws {
                for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
                    let (text, field) = try Self.inks(role, at: size)
                    #expect(field.height > text.height - 0.34, "\(size): text \(text), field \(field)")
                }
            }

            /// Measured: 0.3 to 1.7 pt apart, the title's own figures, for every role whose line is 1.
            @Test(
                "A field of a role on a line of 1 draws its letters where a text of the role does",
                arguments: roles.filter { $0.spec.lineHeight == 1 }
            )
            func tightRole_fieldStandsOnTheText(_ role: LedgerFont.Role) throws {
                for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
                    let (text, field) = try Self.inks(role, at: size)
                    #expect(abs(field.minY - text.minY) < 2, "\(size): text \(text), field \(field)")
                }
            }

            nonisolated static let lowerField: Comment = """
            NF-4: the .top guide of ledgerFieldFont is half of (the field's line − the role's line), which is \
            right for a role whose line is 1 only. A text keeps its letters at the top of its line whatever \
            the line, so a field of .body or .label stands 2.7 pt under its text at .accessibility3 and one \
            of .bodyLight (line 1.6, no guide at all) 8.7 pt. No view uses these today.
            """

            /// **FINDING NF-4** (the API's promise, no screen yet). `.display`, `.heading` and `.subheading`
            /// (lines of 1.06 to 1.1) are 0.3 to 1.3 pt under their text and pass the title's bound.
            @Test(
                "A field of a role on a looser line draws its letters where a text of the role does (known: NF-4)",
                arguments: [LedgerFont.Role.body, .label, .bodyLight]
            )
            func looseRole_fieldStandsOnTheText(_ role: LedgerFont.Role) throws {
                let (text, field) = try Self.inks(role, at: .accessibility3)
                withKnownIssue(Self.lowerField) {
                    #expect(abs(field.minY - text.minY) < 2, "text \(text), field \(field)")
                }
            }
        }
    }
#endif
