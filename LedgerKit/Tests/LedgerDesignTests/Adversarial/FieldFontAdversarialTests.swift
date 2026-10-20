#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
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

            /// The sizes each role is measured at. On the hosted PR runner (`TestSweep`) the default and the
            /// largest, where `.display` stands on the bound.
            nonisolated static let sizes = TestSweep.sizes([DynamicTypeSize.large, .accessibility3, .accessibility5])

            /// The ink of "Gyp" as a text of `role`, and as an edited field of the role over that text.
            static func inks(
                _ role: LedgerFont.Role,
                at size: DynamicTypeSize,
                _ weight: LegibilityWeight = .regular
            ) throws -> (text: CGRect, field: CGRect) {
                func pair(drawsField: Bool) -> some View {
                    FieldFontTests.pair(role, drawsField: drawsField) { $0.ledgerFieldFont(role) }
                }
                return try (
                    FieldFontTests.ink(pair(drawsField: false), at: size, weight, isEdited: false),
                    FieldFontTests.ink(pair(drawsField: true), at: size, weight, isEdited: true)
                )
            }

            @Test("An edited field of every role draws its tails whole", arguments: roles)
            func everyRole_edited_drawsItsTailsWhole(_ role: LedgerFont.Role) throws {
                for size in Self.sizes {
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
                for size in Self.sizes {
                    let (text, field) = try Self.inks(role, at: size)
                    #expect(abs(field.minY - text.minY) < 2, "\(size): text \(text), field \(field)")
                }
            }

            /// Fix round 1 of NF-4 (round 2 of G2): the guide is `(line − 1) × size / 2`, which moves every role
            /// whose line is looser than 1 and not only `.body` and `.label`. Every phone role, at three sizes,
            /// plain and bold: the field's letters within the title's bound of their text, and whole.
            @Test(
                "A field of every role draws its letters where a text of the role does, plain and bold",
                arguments: roles
            )
            func everyRole_fieldStandsOnTheText(_ role: LedgerFont.Role) throws {
                for size in Self.sizes {
                    for weight in [LegibilityWeight.regular, .bold] {
                        let (text, field) = try Self.inks(role, at: size, weight)
                        let down = field.minY - text.minY
                        // Measured: `.display` at `.accessibility5` is the one cell on the bound, 2.0 pt up, plain
                        // and bold (0.0 under the first round's arithmetic); every other cell is inside it.
                        #expect(abs(down) <= 2, "\(size) \(weight): \(down) pt; text \(text), field \(field)")
                        #expect(field.height > text.height - 0.34, "\(size) \(weight): text \(text), field \(field)")
                    }
                }
            }

            /// **FINDING NF-4**, fixed in the chore's fix round 1 (the guide is half of the field's line
            /// less 1): a field of `.body`, `.label` or `.bodyLight` (lines of 1.2 to 1.6) draws its letters
            /// within 2 pt of its text at `.accessibility3`, where it stood 2.7 to 8.7 pt under it.
            @Test(
                "A field of a role on a looser line draws its letters where a text of the role does (known: NF-4)",
                arguments: [LedgerFont.Role.body, .label, .bodyLight]
            )
            func looseRole_fieldStandsOnTheText(_ role: LedgerFont.Role) throws {
                let (text, field) = try Self.inks(role, at: .accessibility3)
                #expect(abs(field.minY - text.minY) < 2, "text \(text), field \(field)")
            }
        }
    }
#endif
