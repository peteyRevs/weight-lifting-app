#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F10 S5, criterion 10: nothing of the page is cut, leaves the phone or lies over something else, at the
    /// default size and at accessibility sizes, on an iPhone 17 and on a 375 pt phone, plain and with Bold
    /// Text, left to right and right to left. By measurement (`WorkoutLayoutProbe`); what it looks like is the
    /// references' (`WorkoutSnapshotTests`), Increase Contrast included.
    @Suite("Workout page layout", .serialized, .tags(.feature))
    struct WorkoutPageLayoutTests {
        nonisolated static let sizes: [DynamicTypeSize] = [.large, .xLarge, .xxxLarge, .accessibility3, .accessibility5]
        nonisolated static let workouts: [WorkoutPreview] = [.started, .minutes, .logging, .dropSet]

        static func page(_ preview: WorkoutPreview) throws -> WorkoutPageModel {
            guard case let .workout(model) = preview.model else {
                throw WorkoutPreview.Unreadable()
            }
            return model.page
        }

        /// A page whose every word is long: a name of three lines, a load of six digits with a fraction, a
        /// last workout as long, and long names remaining.
        static func longWords() throws -> WorkoutPageModel {
            var workout = try Fixtures.seedSession()
            workout.exercises[0].name = "Single-Arm Chest-Supported Dumbbell Row with a Three-Second Pause"
            workout.exercises[0].targetLoad = .pounds(1247.5)
            workout.exercises[0].targetSets = 12
            workout.exercises[0].targetReps = 25
            workout.exercises[0].lastPerformance = LastPerformance(
                date: workout.startedAt.addingTimeInterval(-7 * 24 * 3600), sets: 12, reps: 25, load: .pounds(1242.5)
            )
            workout.exercises[1].name = "Deficit Snatch-Grip Romanian Deadlift from a Two-Inch Platform"
            return WorkoutPresentation.page(
                workout,
                selection: nil,
                isBusy: false,
                WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)
            )
        }

        static func cut(_ model: WorkoutPageModel, at size: DynamicTypeSize) -> [String] {
            let page = WorkoutPage(model: model) { _ in }
            let parts = WorkoutLayoutProbe.parts(of: model)
            return LayoutSetting.sweep(size).flatMap { setting in
                WorkoutLayoutProbe.cut(in: page, parts: parts, setting).map { "\(setting.testDescription): \($0)" }
            }
        }

        static func misplaced(_ model: WorkoutPageModel, at size: DynamicTypeSize) -> [String] {
            let page = WorkoutPage(model: model) { _ in }
            return LayoutSetting.sweep(size).flatMap { setting in
                WorkoutLayoutProbe.misplaced(in: page, setting).map { "\(setting.testDescription): \($0)" }
            }
        }

        @Test("In every state no word of the card or of the list is cut, in any setting", arguments: workouts, sizes)
        func page_noWordIsCut(_ preview: WorkoutPreview, _ size: DynamicTypeSize) throws {
            let cut = try Self.cut(Self.page(preview), at: size)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test("Long names and long numbers wrap and are not cut, in any setting", arguments: sizes)
        func page_longWords_wrap(_ size: DynamicTypeSize) throws {
            let cut = try Self.cut(Self.longWords(), at: size)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "In every state every stop is inside the phone and none lies over another, in any setting",
            arguments: workouts,
            sizes
        )
        func page_nothingLeavesOrOverlaps(_ preview: WorkoutPreview, _ size: DynamicTypeSize) throws {
            let misplaced = try Self.misplaced(Self.page(preview), at: size)
            #expect(misplaced.isEmpty, "\(misplaced.count): \(misplaced.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "With long names and long numbers every stop is inside the phone and none lies over another",
            arguments: sizes
        )
        func page_longWords_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            let misplaced = try Self.misplaced(Self.longWords(), at: size)
            #expect(misplaced.isEmpty, "\(misplaced.count): \(misplaced.prefix(3).joined(separator: "; "))")
        }

        @Test("Every control of the page is a 44 point target in every setting", arguments: sizes)
        func page_controlsAre44Points(_ size: DynamicTypeSize) throws {
            let page = try WorkoutPage(model: Self.page(.logging)) { _ in }
            for setting in LayoutSetting.sweep(size) {
                let controls = setting.elements(of: page).filter { !$0.traits.isDisjoint(with: [.button, .adjustable]) }
                #expect(controls.count == 18, "\(setting.testDescription)")
                let small = controls.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                #expect(small.isEmpty, "\(setting.testDescription): \(small.map(\.label))")
            }
        }

        /// Criterion 19: the two facts are further from each other than a fact's label is from its own value
        /// (`LedgerSpacing.xs`, where they stack), so "Last" is never read with the target's value above it.
        @Test("Between the two facts there is more room than inside one, at every size and setting", arguments: sizes)
        func facts_standApart(_ size: DynamicTypeSize) throws {
            for preview in [WorkoutPreview.started, .logging] {
                let model = try Self.page(preview)
                let card = try #require(model.card)
                let page = WorkoutPage(model: model) { _ in }
                for setting in LayoutSetting.sweep(size) {
                    let stops = setting.elements(of: page)
                    let target = try #require(stops.first { $0.label == "\(card.targetLabel), \(card.target)" })
                    let last = try #require(stops.first { $0.label == "\(card.lastLabel), \(card.last)" })
                    let gap = last.frame.minY - target.frame.maxY
                    #expect(gap >= LedgerSpacing.m - 0.5, "\(preview.rawValue), \(setting.testDescription): \(gap) pt")
                }
            }
        }

        @Test("The check sees a fact that is cut, and passes one that wraps onto more lines")
        func check_seesACut() {
            let label = "Last"
            let value = "Sep 9 · 12×25 @ 1242.5 lb"
            let parts = [LayoutPart("\(label), \(value)") { FactLine(label: label, value: value) }]
            let setting = LayoutSetting()
            let cutOne = FactLine(label: label, value: value).lineLimit(1).frame(width: 120, alignment: .leading)
            #expect(WorkoutLayoutProbe.cut(in: cutOne, parts: parts, setting).count == 1)
            let wrapped = FactLine(label: label, value: value).frame(width: 120, alignment: .leading)
            #expect(WorkoutLayoutProbe.cut(in: wrapped, parts: parts, setting).isEmpty)
            #expect(WorkoutLayoutProbe.cut(in: FactLine(label: label, value: value), parts: parts, setting).isEmpty)
            let missing = [LayoutPart("Not there") { Text(verbatim: "Not there") }]
            #expect(WorkoutLayoutProbe.cut(in: wrapped, parts: missing, setting).count == 1)
        }

        @Test("The check sees a stop that leaves the phone and two that lie over one another")
        func check_seesMisplacedStops() {
            let setting = LayoutSetting(width: 375)
            let wide = Color.clear.frame(width: 500, height: 20)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "Wide"))
            let found = WorkoutLayoutProbe.misplaced(in: wide, setting)
            #expect(found.count == 1, "\(found)")
            let stacked = ZStack {
                Text(verbatim: "Under").frame(width: 100, height: 40)
                Text(verbatim: "Over").frame(width: 100, height: 40)
            }
            #expect(WorkoutLayoutProbe.misplaced(in: stacked, setting).count == 1)
            let apart = VStack { Text(verbatim: "One")
                Text(verbatim: "Two")
            }
            #expect(WorkoutLayoutProbe.misplaced(in: apart, setting).isEmpty)
        }
    }
#endif
