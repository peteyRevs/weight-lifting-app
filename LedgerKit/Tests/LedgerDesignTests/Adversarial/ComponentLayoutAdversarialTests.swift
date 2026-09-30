#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// Two views that should render differently.
    struct ViewPair {
        let name: String
        let first: AnyView
        let second: AnyView

        init(_ name: String, _ first: some View, _ second: some View) {
            self.name = name
            self.first = AnyView(first)
            self.second = AnyView(second)
        }

        /// The view enabled, then disabled.
        static func disabling(_ name: String, _ view: some View) -> Self {
            Self(name, view, view.disabled(true))
        }
    }

    /// The content the layout suite squeezes the components with.
    enum LayoutCases {
        static func setRow(number: String = "3", weight: String, reps: String = "5") -> some View {
            SetRow(number: number, weight: weight, reps: reps, state: .pending, checkLabel: "Log set") {} onCheck: {}
        }

        /// Pairs of views that differ only in their last character.
        static func lastCharacterPairs() -> [ViewPair] {
            let name = "Single-Arm Dumbbell Romanian Deadlift, Paused"
            return [
                ViewPair("SetRow, weight 1,002.5", setRow(weight: "1,002.5"), setRow(weight: "1,002.0")),
                ViewPair("SetRow, weight 102.5", setRow(weight: "102.5"), setRow(weight: "102.0")),
                ViewPair(
                    "SetRow, reps 12",
                    setRow(weight: "1,002.5", reps: "12"),
                    setRow(weight: "1,002.5", reps: "13")
                ),
                ViewPair("SetRow, label 12", setRow(number: "12", weight: "185"), setRow(number: "13", weight: "185")),
                ViewPair(
                    "HairlineRow, long title with accessory",
                    HairlineRow("\(name) 1", detail: "3 × 8 @ 1,002.5 lb") {
                        Text(verbatim: "5 × 5 @ 185").ledgerFont(.numeralS)
                    },
                    HairlineRow("\(name) 2", detail: "3 × 8 @ 1,002.5 lb") {
                        Text(verbatim: "5 × 5 @ 185").ledgerFont(.numeralS)
                    }
                ),
                ViewPair(
                    "PrimaryButton, long title with icon",
                    PrimaryButton("Resume Upper A — Push focus · 1:12:48", icon: .arrow) {},
                    PrimaryButton("Resume Upper A — Push focus · 1:12:49", icon: .arrow) {}
                ),
                ViewPair(
                    "PillButton, long title",
                    PillButton("Repeat last session's sets 1") {},
                    PillButton("Repeat last session's sets 2") {}
                ),
                ViewPair(
                    "Eyebrow, long",
                    Eyebrow("Estimated 1RM · 8 weeks · 1"),
                    Eyebrow("Estimated 1RM · 8 weeks · 2")
                )
            ]
        }

        static func enabledAndDisabled() -> [ViewPair] {
            [
                .disabling("PrimaryButton", PrimaryButton("Save workout") {}),
                .disabling("PrimaryButton with icon", PrimaryButton("Start workout", icon: .arrow) {})
            ]
        }
    }

    extension RenderingSuites {
        /// F06 slice 2, adversarial round 1: Dynamic Type up to AX5 and Bold Text with the content that
        /// squeezes the components: four-digit weights, long exercise names and titles, long step labels.
        ///
        /// Truncation is found without reading text: two strings that differ only in their last
        /// character render differently unless that character is cut off ("1,00…"). Numerals are
        /// tabular, so both strings lay out the same.
        @Suite("Component layout (adversarial, slice 2 round 1)", .tags(.design))
        struct ComponentLayoutAdversarialTests {
            nonisolated static let sizes: [DynamicTypeSize] = [
                .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5
            ]

            /// The view on a phone screen: the screen inset, the ground, 402 pt wide, its own height.
            static func page(_ view: some View, _ size: DynamicTypeSize, bold: Bool = false) throws -> PixelBuffer {
                let content = view
                    .padding(LedgerSpacing.screen)
                    .frame(width: SnapshotConfig.phoneWidth)
                    .background(LedgerColor.ground)
                    .environment(\.legibilityWeight, bold ? .bold : .regular)
                let image = try #require(
                    RenderedImage.render(content, width: SnapshotConfig.phoneWidth, dynamicTypeSize: size)
                )
                return try #require(PixelBuffer(image))
            }

            /// The probe's positive control: a weight no column can hold is cut ("1,002,0…") at AX5, and
            /// the two renders are then identical. Without this, "they differ" could be vacuous.
            @Test("The truncation probe sees a cut: an absurd weight renders the same whatever its last digit")
            func truncationProbe_absurdWeight_isSeenAsCut() throws {
                let one = try Self.page(LayoutCases.setRow(weight: "1,002,002,002,002.5"), .accessibility5)
                let other = try Self.page(LayoutCases.setRow(weight: "1,002,002,002,002.0"), .accessibility5)
                #expect(one == other)
            }

            @Test(
                "Nothing is cut off at the end: four-digit weights, long names and titles, up to AX5",
                arguments: sizes
            )
            func longContent_lastCharacter_isDrawn(size: DynamicTypeSize) throws {
                for pair in LayoutCases.lastCharacterPairs() {
                    for bold in [false, true] {
                        let one = try Self.page(pair.first, size, bold: bold)
                        let other = try Self.page(pair.second, size, bold: bold)
                        #expect(
                            one != other,
                            "\(pair.name), \(size)\(bold ? ", Bold Text" : ""): the last character is cut off"
                        )
                    }
                }
            }

            @Test(
                "Nothing grows wider than the screen: set rows and steppers with long content, up to AX5",
                arguments: sizes
            )
            func longContent_width_staysOnScreen(size: DynamicTypeSize) throws {
                let content = SnapshotConfig.phoneWidth - 2 * LedgerSpacing.screen
                let views: [(String, AnyView)] = [
                    ("SetRow 1,002.5 × 12", AnyView(LayoutCases.setRow(number: "12", weight: "1,002.5", reps: "12"))),
                    (
                        "SetRowSteppers 2.5 kg / 1 rep",
                        AnyView(SetRowSteppers(
                            weightStep: "2.5 kg",
                            repStep: "1 rep",
                            weight: "82.5 kilograms",
                            reps: "12 reps",
                            onWeight: { _ in },
                            onReps: { _ in }
                        ))
                    ),
                    ("SetRowHeader", AnyView(SetRowHeader(number: "#", weight: "lb", reps: "reps")))
                ]
                for (name, view) in views {
                    for bold in [false, true] {
                        let image = try #require(
                            RenderedImage.render(
                                view.environment(\.legibilityWeight, bold ? .bold : .regular),
                                width: content,
                                dynamicTypeSize: size
                            )
                        )
                        #expect(
                            CGFloat(image.width) <= content,
                            "\(name), \(size)\(bold ? ", Bold Text" : ""): \(image.width) pt wide in \(content)"
                        )
                    }
                }
            }

            /// `LedgerPressStyle` leaves the disabled look to the label. `PrimaryButton` draws one;
            /// `PillButton` and `IconPillButton` have none by design (slice 2 notes, decision 7), so
            /// they are not asserted here.
            @Test(
                "A disabled PrimaryButton looks different from an enabled one",
                arguments: [ColorScheme.light, .dark]
            )
            func disabledPrimaryButton_looksDisabled(scheme: ColorScheme) throws {
                for pair in LayoutCases.enabledAndDisabled() {
                    let render = { (view: AnyView) in
                        RenderedImage.render(view.background(LedgerColor.ground), colorScheme: scheme)
                            .flatMap(PixelBuffer.init)
                    }
                    let one = try #require(render(pair.first))
                    let other = try #require(render(pair.second))
                    #expect(one != other, "\(pair.name) (\(scheme)): disabled is pixel-identical to enabled")
                }
            }
        }
    }
#endif
