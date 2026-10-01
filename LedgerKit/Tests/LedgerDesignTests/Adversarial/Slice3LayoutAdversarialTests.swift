#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// Slice 3's phone components with content longer than the gallery's, from v2's own screens.
    enum Slice3LayoutCases {
        /// Today's two tiles with a heavy week.
        static func todayTiles(volume: String, delta: String = "+12.5%") -> some View {
            StatTileRow {
                StatTile(value: "3", unit: "/4", caption: "sessions this week")
                StatTile(value: volume, unit: "k", caption: "lb moved", delta: delta)
            }
        }

        /// Exercise history's three tiles for a strong lifter.
        static func historyTiles(
            oneRM: String = "402.5",
            reps: String = "×12",
            sessions: String = "1,248"
        ) -> some View {
            StatTileRow {
                StatTile(value: oneRM, caption: "1RM est")
                StatTile(value: "365", unit: reps, caption: "best set")
                StatTile(value: sessions, caption: "sessions")
            }
        }

        static func week(lastWeekday: String, lastDate: String) -> some View {
            WeekStrip(days: Array(Slice3Weeks.sundayFirst.dropLast()) + [
                Slice3Weeks.day(lastWeekday, lastDate, .planned, "Saturday")
            ])
        }

        static func sheet(title: String, cancel: String = "Cancel") -> some View {
            SheetChrome(title, cancel: cancel) {} content: {
                Text(verbatim: "Same movement pattern, equipment you have.")
            }
        }

        static func empty(action: String) -> some View {
            EmptyState(
                "Nothing logged for Single-Arm Dumbbell Romanian Deadlift yet",
                body: "Log a set of it in a workout and its history starts here.",
                actionTitle: action
            ) {}
        }

        /// A long sheet title is not here: `ImageRenderer` cuts it at some accessibility sizes where a hosted
        /// view at the same ideal height does not, so this probe cannot judge it.
        /// `Slice3AccessibilityAdversarialTests` measures the title in a hosted sheet instead.
        static func lastCharacterPairs() -> [ViewPair] {
            [
                ViewPair("StatTile, weekly volume 124.8k", todayTiles(volume: "124.8"), todayTiles(volume: "124.9")),
                ViewPair(
                    "StatTile, delta +12.5%",
                    todayTiles(volume: "41.2"),
                    todayTiles(volume: "41.2", delta: "+12.6%")
                ),
                ViewPair("StatTile, 1RM 402.5 of three", historyTiles(), historyTiles(oneRM: "402.6")),
                ViewPair("StatTile, unit ×12 of three", historyTiles(), historyTiles(reps: "×13")),
                ViewPair("StatTile, 1,248 sessions of three", historyTiles(), historyTiles(sessions: "1,249")),
                ViewPair(
                    "WeekStrip, date 31",
                    week(lastWeekday: "S", lastDate: "31"),
                    week(lastWeekday: "S", lastDate: "30")
                ),
                ViewPair(
                    "WeekStrip, weekday Sat",
                    week(lastWeekday: "Sat", lastDate: "5"),
                    week(lastWeekday: "Sau", lastDate: "5")
                ),
                ViewPair(
                    "SheetChrome, cancel",
                    sheet(title: "Swap exercise"),
                    sheet(title: "Swap exercise", cancel: "Cancem")
                ),
                ViewPair("EmptyState, action", empty(action: "Clear all filters"), empty(action: "Clear all filtert"))
            ]
        }
    }

    extension RenderingSuites {
        /// F06 slice 3, adversarial round 1: long content up to AX5 with and without Bold Text, and the
        /// progress bar and week strip as drawn.
        @Suite("Slice 3 layout (adversarial, slice 3 round 1)", .tags(.design))
        struct Slice3LayoutAdversarialTests {
            nonisolated static let sizes: [DynamicTypeSize] = [
                .large,
                .xxxLarge,
                .accessibility1,
                .accessibility3,
                .accessibility5
            ]

            static func page(_ view: some View, _ size: DynamicTypeSize, _ bold: Bool) throws -> PixelBuffer {
                try ComponentLayoutAdversarialTests.page(view, size, bold: bold)
            }

            @Test("The probe sees a cut: an absurd 1RM in a row of three renders the same whatever its last digit")
            func truncationProbe_absurdValue_isSeenAsCut() throws {
                let one = try Self.page(Slice3LayoutCases.historyTiles(oneRM: "1,002,002,002,002.5"), .xxxLarge, false)
                let other = try Self.page(
                    Slice3LayoutCases.historyTiles(oneRM: "1,002,002,002,002.0"),
                    .xxxLarge,
                    false
                )
                #expect(one == other)
            }

            @Test("Nothing is cut off at the end: long values, dates, titles and actions, up to AX5", arguments: sizes)
            func longContent_lastCharacter_isDrawn(size: DynamicTypeSize) throws {
                for pair in Slice3LayoutCases.lastCharacterPairs() {
                    for bold in [false, true] {
                        let one = try Self.page(pair.first, size, bold)
                        let other = try Self.page(pair.second, size, bold)
                        #expect(one != other, "\(pair.name), \(size)\(bold ? ", Bold Text" : ""): the end is cut off")
                    }
                }
            }

            /// `bar` on black at `width`: every segment done, so each one is `inkMuted` ink.
            static func bar(_ lengths: [Int], width: CGFloat) throws -> PixelBuffer {
                let segments = lengths.map { ProgressSegment(length: $0, state: .done) }
                let view = ProgressSegments(segments, label: "Workout progress", value: "")
                    .frame(width: width)
                    .background(Color.black)
                let image = try #require(RenderedImage.render(view, width: width))
                return try #require(PixelBuffer(image))
            }

            /// The columns of `buffer` with ink, as runs.
            static func inkedRuns(_ buffer: PixelBuffer) -> [ClosedRange<Int>] {
                let black = Pixel(hex: 0x000000)
                var runs: [ClosedRange<Int>] = []
                for column in 0 ..< buffer.width {
                    let inked = (0 ..< buffer.height).contains { buffer.pixel(column: column, row: $0).differs(
                        from: black,
                        by: 24
                    ) }
                    guard inked else { continue }
                    if let last = runs.last, last.upperBound == column - 1 {
                        runs[runs.count - 1] = last.lowerBound ... column
                    } else {
                        runs.append(column ... column)
                    }
                }
                return runs
            }

            @Test("ProgressSegments spans the width: v2's five exercises start at the edge and end at the edge")
            func progressSegments_fiveExercises_spanTheWidth() throws {
                let runs = try Self.inkedRuns(Self.bar([5, 3, 4, 3, 3], width: 350))
                #expect(runs.count == 5, "\(runs)")
                #expect(runs.first?.lowerBound == 0 && runs.last?.upperBound == 349, "\(runs)")
            }

            /// "Zero or less draws nothing" (ProgressSegment.length's doc): nothing includes the 3 pt gap.
            @Test("A segment of no sets leaves no gap: the bar still starts at the edge, one gap between the rest")
            func progressSegments_zeroLengthSegment_leavesNoGap() throws {
                let leading = try Self.inkedRuns(Self.bar([0, 3], width: 100))
                #expect(leading.first?.lowerBound == 0, "[0, 3] at 100 pt: ink \(leading)")
                let middle = try Self.inkedRuns(Self.bar([3, 0, 3], width: 100))
                #expect(middle.count == 2, "\(middle)")
                if middle.count == 2 {
                    let gap = middle[1].lowerBound - middle[0].upperBound - 1
                    #expect(gap == Int(ProgressSegments.gap), "[3, 0, 3] at 100 pt: a \(gap) pt gap, ink \(middle)")
                }
            }

            @Test("Right to left, today's orange is in today's column counted from the right")
            func weekStrip_rightToLeft_drawsTodayFromTheRight() throws {
                let width = SnapshotConfig.phoneWidth
                func orangeMidX(_ direction: LayoutDirection) throws -> Double {
                    let view = WeekStripGallery().frame(width: width).background(Color.black)
                        .environment(\.layoutDirection, direction)
                    let buffer = try #require(RenderedImage.render(view, width: width).flatMap(PixelBuffer.init))
                    let orange = (0 ..< buffer.width).filter { column in
                        (0 ..< buffer.height).contains {
                            let pixel = buffer.pixel(column: column, row: $0)
                            return pixel.red > 200 && pixel.green < 140 && pixel.blue < 90
                        }
                    }
                    let first = try #require(orange.first), last = try #require(orange.last)
                    return Double(first + last) / 2
                }
                let ltr = try orangeMidX(.leftToRight)
                let rtl = try orangeMidX(.rightToLeft)
                #expect(ltr < Double(width) / 2, "Wednesday is the third of seven: \(ltr)")
                #expect(abs(rtl - (Double(width) - 1 - ltr)) <= 2, "LTR \(ltr), RTL \(rtl)")
            }
        }
    }
#endif
