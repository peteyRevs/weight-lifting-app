#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S5 criteria 1, 9 and 10: the page's views on states no preview draws, read as VoiceOver reads
    /// them against the tester's own tables; what each stop sends; the set rows' numerals, which the
    /// implementer's cut check leaves out; where the page is orange; and where the page stands in its scroll
    /// view when the shown exercise changes.
    @Suite("Workout page views (adversarial)", .serialized, .tags(.feature))
    struct WorkoutPageViewsAdversarialTests {
        static let context = WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)

        static func page(
            _ state: WorkoutState,
            selection: WorkoutSelection? = nil,
            isBusy: Bool = false
        ) -> WorkoutPageModel {
            WorkoutPresentation.page(state, selection: selection, isBusy: isBusy, context)
        }

        /// The spec's five straight exercises with every set logged: the page shows the last, all done.
        static func everySetLogged() -> WorkoutState {
            var state = EventBuilders.seedSession()
            for index in state.exercises.indices {
                for row in state.exercises[index].sets.indices {
                    state.exercises[index].sets[row].doneAt = Fixtures.now
                }
            }
            state.cursor = Cursor(exerciseIndex: 4, setIndex: 2)
            return state
        }

        static func stops(of model: WorkoutPageModel, _ appearance: SnapshotAppearance) -> [Stop] {
            WorkoutPage(model: model) { _ in }.accessibilityElements(appearance).map {
                Stop($0.label, value: $0.value, $0.traits)
            }
        }

        // MARK: The tester's own trees

        @Test("Every set logged: the last exercise's card reads as its rows done, with no steppers and no list")
        func tree_everySetLogged() {
            var expected = [
                Stop("Exercise 5 of 5", .staticText),
                Stop("Cable Lateral Raise", [.header, .staticText]),
                Stop("TARGET, 3 × 15 @ 15 lb · RPE 8", .staticText),
                Stop("Last, No history yet", .staticText),
                Stop("#, lb, reps", .staticText)
            ]
            for number in 1 ... 3 {
                expected.append(Stop("Set \(number), 15 pounds, 15 reps", value: "Done", .button))
                expected.append(Stop("Undo set \(number)", value: "Done", [.button, .selected]))
            }
            expected.append(Stop("+ Add set", .button))
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = Self.stops(of: Self.page(Self.everySetLogged()), appearance)
                #expect(firstDifference(found: found, expected: expected) == nil, "\(appearance)")
            }
        }

        @Test("A cursor that names no row: the page is the list alone, every exercise a button")
        func tree_noCard() {
            var state = EventBuilders.seedSession()
            state.cursor = nil
            let expected = [Stop("REMAINING", [.header, .staticText])] + [
                "Barbell Bench Press, 5 × 5", "Incline DB Press, 3 × 10", "Chest-Supported Row, 4 × 8",
                "Lat Pulldown, 3 × 12", "Cable Lateral Raise, 3 × 15"
            ].map { Stop($0, .button) }
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = Self.stops(of: Self.page(state), appearance)
                #expect(firstDifference(found: found, expected: expected) == nil, "\(appearance)")
            }
        }

        @Test(
            "Each stop of such pages sends exactly its own tap, once; while busy every control is dimmed and sends none"
        )
        func stops_sendTheirOwnTap_once() {
            let state = Self.everySetLogged()
            let sets = state.exercises[4].sets.map(\.id)
            var sent: [WorkoutAction] = []
            WorkoutPage(model: Self.page(state)) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            let expected = sets.flatMap {
                [WorkoutEdit.select(exerciseIndex: 4, setID: $0), .unlog(exerciseIndex: 4, setID: $0)]
            } + [.addSet(exerciseIndex: 4)]
            #expect(sent == expected.map(WorkoutAction.edit))

            sent = []
            let busy = WorkoutPage(model: Self.page(state, isBusy: true)) { sent.append($0) }
            let controls = busy.accessibilityElements().filter { $0.traits.contains(.button) }
            #expect(controls.count == 7 && controls.allSatisfy { $0.traits.contains(.notEnabled) })
            busy.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.isEmpty)
        }

        // MARK: The set rows' numerals (criterion 10; the implementer's cut check leaves them out)

        /// The width `text` takes by itself in `setting`, in the font of `role`.
        static func natural(_ text: String, _ role: LedgerFont.Role, _ setting: LayoutSetting) -> CGFloat {
            let alone = Text(verbatim: text).ledgerFont(role).fixedSize()
            return setting.elements(of: alone, fixedWidth: false).first?.frame.width ?? .infinity
        }

        /// What a set row cuts in `setting`. `LedgerDesign.SetRow` draws a numeral on one line and shrinks it
        /// to half its size at most (`minimumScaleFactor(0.5)`); one that needs more than twice its column is
        /// cut with an ellipsis. The columns are `SetColumns`': the label's, 22/12 of the caption's size,
        /// then two equal ones.
        static func cut(label: String, weight: String, reps: String, _ setting: LayoutSetting) -> [String] {
            let row = SetRow(
                number: label, weight: weight, reps: reps, state: .active, checkLabel: "Check",
                accessibilitySummary: "Row", onSelect: {}, onCheck: {}
            )
            .padding(.horizontal, LedgerSpacing.screen)
            guard let body = setting.elements(of: row).first(where: { $0.label == "Row" }) else {
                return ["the row was not found"]
            }
            let labelColumn = LedgerFont.scaledSize(.caption, dynamicTypeSize: setting.size) * 22 / 12
            let column = (body.frame.width - labelColumn - 2 * LedgerSpacing.s) / 2
            var found: [String] = []
            for (name, value) in [("weight", weight), ("reps", reps)] {
                let needs = natural(value, .numeralM, setting)
                if needs / 2 > column + 0.5 {
                    found.append("\(name) \(value) needs \(Int(needs)) pt and has \(Int(column))")
                }
            }
            return found
        }

        @Test(
            "A weight of five characters and reps of two are drawn whole in a set row, at every size and setting",
            arguments: WorkoutPageLayoutTests.sizes,
            [("187.5", "12"), ("102.5", "10"), ("315", "5"), ("47.5", "15")]
        )
        func numerals_areNotCut(size: DynamicTypeSize, values: (weight: String, reps: String)) {
            let cut = LayoutSetting.sweep(size).flatMap { setting in
                Self.cut(label: "10", weight: values.weight, reps: values.reps, setting).map {
                    "\(setting.testDescription): \($0)"
                }
            }
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test("The check sees a numeral that cannot fit at half its size, and passes one that fits")
        func numeralCheck_seesACut() {
            let narrow = LayoutSetting(size: .accessibility5, width: 375, isBold: true)
            #expect(Self.cut(label: "1", weight: "1234567.25", reps: "5", narrow).count == 1)
            #expect(Self.cut(label: "1", weight: "5", reps: "5", LayoutSetting()).isEmpty)
        }
    }

    extension WorkoutPageViewsAdversarialTests {
        // MARK: Orange (criterion 9)

        /// The rows of `image` that hold a pixel of the accent: saturated orange, as `LedgerColor.accentText`
        /// is in either appearance (`#B2390E` on paper, `#FF5B22` on ink).
        static func orangeRows(of image: CGImage) -> [Int] {
            guard let buffer = PixelBuffer(image) else {
                return []
            }
            return (0 ..< buffer.height).filter { line in
                buffer.pixels[line * buffer.width ..< (line + 1) * buffer.width].contains { pixel in
                    let (red, green, blue) = (Int(pixel.red), Int(pixel.green), Int(pixel.blue))
                    return red >= 150 && green * 2 <= red && blue * 3 <= red
                }
            }
        }

        @Test(
            "Orange is drawn in the shown row and in the logged rows' discs, and nowhere else on the page",
            arguments: [WorkoutPreview.started, .logging, .dropSet],
            [ColorScheme.light, .dark]
        )
        func orange_isOnlyInTheSetRows(_ preview: WorkoutPreview, scheme: ColorScheme) throws {
            let model = try WorkoutPageLayoutTests.page(preview)
            let card = try #require(model.card)
            let page = WorkoutPage(model: model) { _ in }
            let width = SnapshotConfig.phoneWidth
            let image = try #require(RenderedImage.render(
                page,
                width: width,
                colorScheme: scheme,
                dynamicTypeSize: .large
            ))
            let scale = CGFloat(image.width) / width
            let orange = Self.orangeRows(of: image).map { CGFloat($0) / scale }
            #expect(!orange.isEmpty, "the check cannot see orange in this appearance")
            // Where orange may be: the shown row (with the rule over it) and the rows that are logged.
            let allowed = card.rows.filter { $0.state != .pending }.map(\.summary)
            // The reader hosts the page wherever it likes: a marker over the page says where its top is.
            let marked = VStack(spacing: 0) {
                Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                page
            }
            let stops = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, .large))
            let top = try #require(stops.first { $0.label == "Top" }).frame.maxY
            let frames = stops.filter { allowed.contains($0.label) }.map {
                $0.frame.offsetBy(dx: 0, dy: -top).insetBy(dx: 0, dy: -10)
            }
            #expect(frames.count == allowed.count)
            let stray = orange.filter { line in !frames.contains { $0.minY <= line && line <= $0.maxY } }
            #expect(
                stray.isEmpty,
                "\(stray.count) lines of pixels are orange outside the set rows, from y \(stray.first ?? 0)"
            )
        }

        // MARK: The scroll view (criterion 1; the reviewer's S-2)

        static func scrollView(in view: UIView) -> UIScrollView? {
            (view as? UIScrollView) ?? view.subviews.lazy.compactMap(scrollView(in:)).first
        }

        /// The real screen at the largest size of the matrix, showing `selection`'s exercise.
        static func screen(_ state: WorkoutState, _ selection: WorkoutSelection?) -> AnyView {
            let model = WorkoutPresentation.screen(
                .loaded(state), selection: selection, isBusy: false, locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
            return AnyView(
                WorkoutScreen(model: model) { _ in }
                    .environment(\.workoutTimeline, .fixed(at: Fixtures.now))
                    .environment(\.dynamicTypeSize, .accessibility3)
            )
        }

        /// FINDING F10-S5-5 (the reviewer's S-2): the page keeps its scroll position when the shown exercise
        /// changes, so after a jump from "REMAINING", which is at the page's end, the new exercise's name and
        /// place are above the screen. `WorkoutScreen`'s scroll view has no position of its own.
        @Test("When the shown exercise changes, the page stands at its top again; a change within it does not move it")
        func scroll_returnsToTheTop_whenTheExerciseChanges() throws {
            var state = EventBuilders.seedSession()
            let host = UIHostingController(rootView: Self.screen(state, nil))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let settle = {
                for _ in 0 ..< 5 {
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
            }
            settle()
            let first = try #require(Self.scrollView(in: host.view))
            #expect(first.contentSize.height > first.bounds.height + 250, "the page is too short to tell")
            first.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
            // A "+" on the shown row: the same exercise, and the page stays where the lifter scrolled it.
            state.exercises[0].sets[0].weight = .pounds(190)
            host.rootView = Self.screen(state, nil)
            settle()
            let offset = try #require(Self.scrollView(in: host.view)).contentOffset.y
            #expect(abs(offset - 250) < 1, "a change within the exercise moved the page to \(offset)")
            // A tap on the fourth exercise in "REMAINING".
            let jump = WorkoutSelection(exerciseIndex: 3, setID: state.exercises[3].sets[0].id)
            host.rootView = Self.screen(state, jump)
            settle()
            let after = try #require(Self.scrollView(in: host.view)).contentOffset.y
            #expect(after < 1, "the new exercise's card starts \(after) pt above the screen")
        }
    }
#endif
