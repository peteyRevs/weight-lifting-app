#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F15-S2-10: the cover's header never breaks a word. At the accessibility sizes the running app drew
    /// "Minimi / ze" and "Finis / h"; the ruling: one row while it fits, else the buttons under the time, never a
    /// smaller type or a truncation. Each button is measured by itself, with all the width it wants, and in the
    /// header: in the header it is as wide as by itself and no taller, so its word stands on one line.
    @Suite("Workout header layout", .serialized, .tags(.feature))
    struct WorkoutHeaderLayoutTests {
        static func header() throws -> WorkoutHeaderModel {
            guard case let .workout(model) = WorkoutPreview.minutes.model else {
                throw WorkoutPreview.Unreadable()
            }
            return model.header
        }

        @Test(
            "Minimize and Finish each stand whole on one line, at Accessibility 3 and 5, in every setting",
            arguments: [DynamicTypeSize.accessibility3, .accessibility5]
        )
        func buttons_areWholeWords(_ size: DynamicTypeSize) throws {
            let model = try Self.header()
            let header = WorkoutHeader(model: model) { _ in }
                .environment(\.workoutTimeline, .fixed(at: WorkoutPreview.minutes.now))
            for setting in LayoutSetting.everySetting(size) {
                let drawn = setting.elements(of: header)
                for (title, ink) in [(model.minimize, PillStyle.ghost), (model.finish, .outline)] {
                    let alone = setting.elements(of: ink.button(title).fixedSize(), fixedWidth: false)
                    let whole = try #require(alone.first?.frame.size, "\(title) alone")
                    let given = try #require(drawn.first { $0.label == title }?.frame.size, "\(title) in the header")
                    let isWhole = given.width >= whole.width - 0.5 && given.height <= whole.height + 0.5
                    #expect(isWhole, "\(setting.testDescription): \(title) takes \(whole), is given \(given)")
                }
                let misplaced = WorkoutLayoutProbe.misplaced(in: header, setting)
                #expect(misplaced.isEmpty, "\(setting.testDescription): \(misplaced)")
            }
        }

        /// At the default size the header keeps v2's one row: the time between the two buttons.
        @Test("At the default size the buttons and the time stand in one row")
        func defaultSize_isOneRow() throws {
            let model = try Self.header()
            let header = WorkoutHeader(model: model) { _ in }
                .environment(\.workoutTimeline, .fixed(at: WorkoutPreview.minutes.now))
            let drawn = LayoutSetting().elements(of: header)
            let minimize = try #require(drawn.first { $0.label == model.minimize }).frame
            let time = try #require(drawn.first { $0.label == model.elapsedLabel }).frame
            let finish = try #require(drawn.first { $0.label == model.finish }).frame
            let isOneRow = abs(minimize.midY - time.midY) < 1 && abs(finish.midY - time.midY) < 1
                && minimize.maxX <= time.minX && time.maxX <= finish.minX
            #expect(isOneRow, "\(minimize), \(time), \(finish)")
        }

        /// G3 N5: VoiceOver reads "Minimize", the time, then "Finish", whatever the arrangement: one line, the time
        /// over the buttons, or one line each (a phone narrower than any, 200 pt, at the largest size).
        @Test(
            "VoiceOver reads Minimize, the time, then Finish on one line, two or three",
            arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5]
        )
        func readingOrder_staysTheRows(_ size: DynamicTypeSize) throws {
            let model = try Self.header()
            let header = WorkoutHeader(model: model) { _ in }
                .environment(\.workoutTimeline, .fixed(at: WorkoutPreview.minutes.now))
            let expected = [model.minimize, model.elapsedLabel, model.finish]
            for setting in LayoutSetting.everySetting(size) + [LayoutSetting(size: size, width: 200)] {
                let labels = Array(setting.elements(of: header).prefix(3).map(\.label))
                #expect(labels == expected, "\(setting.testDescription): \(labels)")
            }
            guard size == .accessibility5 else {
                return
            }
            let narrow = LayoutSetting(size: size, width: 200).elements(of: header)
            let minimize = try #require(narrow.first { $0.label == model.minimize }).frame
            let finish = try #require(narrow.first { $0.label == model.finish }).frame
            #expect(finish.minY >= minimize.maxY - 0.5, "at 200 pt each button has a line: \(minimize), \(finish)")
        }

        /// The three arrangements, by the subviews' own widths (Minimize, the time, Finish) and the width there is.
        @Test("One line while all three fit, then the time over the buttons, then one line each")
        func rows_byTheWidthThereIs() {
            let sizes = [CGSize(width: 100, height: 44), CGSize(width: 60, height: 20), CGSize(width: 80, height: 44)]
            let rows = { (width: CGFloat) in HeaderRowLayout.rows(sizes, within: width, spacing: 8) }
            #expect(rows(256) == [[0, 1, 2]])
            #expect(rows(255) == [[1], [0, 2]])
            #expect(rows(188) == [[1], [0, 2]])
            #expect(rows(187) == [[1], [0], [2]])
        }

        /// The header's two pill styles, to measure a button by itself.
        enum PillStyle {
            case ghost, outline

            @MainActor
            func button(_ title: String) -> PillButton {
                self == .ghost ? PillButton(title, style: .ghost, flush: .leading) {} : PillButton(title) {}
            }
        }
    }
#endif
