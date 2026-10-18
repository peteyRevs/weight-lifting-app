#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// G2, F10 S7a criteria 6 and 38 to 40: the "End workout?" sheet's parts at every text size the system
    /// has, on both widths, with Bold Text and right to left: VoiceOver's order, every stop on the phone and
    /// clear of the others, 44 pt targets, and orange by pixel in every one of those settings.
    @MainActor
    @Suite("End workout? sheet (adversarial)", .serialized, .tags(.feature), .timeLimit(.minutes(3)))
    struct FinishSheetAdversarialTests {
        /// Every size the system has, the five below the default included.
        nonisolated static let sizes = DynamicTypeSize.allCases

        /// The longest line the sheet can be asked for, and the shortest.
        static func models() throws -> [WorkoutFinishModel] {
            let words = WorkoutFinishWordsAdversarialTests.self
            return try [(1250, 1234), (25, 23), (1, 0), (1, 1)].flatMap { total, done in
                try [false, true].map { isSaving in
                    try WorkoutPresentation.finishSheet(
                        words.workout(sets: total, done: done), isSaving: isSaving, locale: Fixtures.locale
                    )
                }
            }
        }

        @Test(
            "VoiceOver reads title, Keep lifting, the line, Save workout, Discard, in every setting",
            arguments: sizes
        )
        func order_isTheCriterias(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                for setting in LayoutSetting.sweep(size) {
                    let stops = setting.elements(of: FinishSheetParts(model: model))
                    let name = "\(setting.testDescription), \(model.summary)\(model.isEnabled ? "" : ", saving")"
                    #expect(stops.map(\.label) == [
                        "End workout?", "Keep lifting", model.spokenSummary, "Save workout", "Discard"
                    ], "\(name)")
                    guard stops.count == 5 else {
                        continue
                    }
                    #expect(stops[0].traits.contains(.header), "\(name)")
                    #expect(stops[2].label.contains(" · ") == false, "\(name): the dot is for the eye")
                    #expect(stops[1 ... 4].map { $0.traits.contains(.button) } == [true, false, true, true], "\(name)")
                    #expect(stops[3].traits.contains(.notEnabled) == !model.canSave, "\(name)")
                    #expect(stops[4].traits.contains(.notEnabled) == !model.isEnabled, "\(name)")
                    #expect(stops[1].traits.contains(.notEnabled) == !model.isEnabled, "\(name)")
                    // Reading order is drawing order: nothing VoiceOver reads later stands higher.
                    let line = stops[2].frame
                    #expect(line.maxY <= stops[3].frame.minY + 0.5, "\(name): the line runs into Save workout")
                    #expect(stops[3].frame.maxY <= stops[4].frame.minY + 0.5, "\(name)")
                    #expect(max(stops[0].frame.maxY, stops[1].frame.maxY) <= line.minY + 0.5, "\(name)")
                }
            }
        }

        @Test(
            "Every stop is on the phone, clear of the others, and a button is 44 pt, in every setting",
            arguments: sizes
        )
        func stops_areOnThePhone(_ size: DynamicTypeSize) throws {
            for model in try Self.models() where model.isEnabled {
                for setting in LayoutSetting.sweep(size) {
                    let stops = setting.elements(of: FinishSheetParts(model: model))
                    let name = "\(setting.testDescription), \(model.summary)"
                    // The reader hosts at the iPhone 17's width, a narrower phone at its leading edge.
                    let left = setting.isRightToLeft ? SnapshotConfig.phoneWidth - setting.width : 0
                    for stop in stops {
                        let frame = stop.frame
                        let isInside = frame.minX >= left - 0.5 && frame.maxX <= left + setting.width + 0.5
                        #expect(isInside, "\(name): \(stop.label) \(frame)")
                        #expect(frame.width > 1 && frame.height > 1, "\(name): \(stop.label) \(frame)")
                        if stop.traits.contains(.button) {
                            #expect(frame.width >= 43.999 && frame.height >= 43.999, "\(name): \(stop.label) \(frame)")
                        }
                    }
                    for (index, one) in stops.enumerated() {
                        for other in stops[(index + 1)...] {
                            let shared = one.frame.intersection(other.frame)
                            let overlaps = !shared.isNull && shared.width > 0.5 && shared.height > 0.5
                            #expect(!overlaps, "\(name): \(one.label) lies over \(other.label)")
                        }
                    }
                }
            }
        }

        struct Orange {
            let found: Int
            let stray: Int
            let `where`: String
        }

        /// The orange pixels of the sheet drawn in `setting` and `scheme`, and how many lie outside the frame
        /// of "Save workout".
        static func orange(
            _ model: WorkoutFinishModel,
            _ setting: LayoutSetting,
            _ scheme: ColorScheme
        ) throws -> Orange {
            let sheet = FinishSheetParts(model: model)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
            let image = try #require(RenderedImage.render(
                sheet, width: setting.width, colorScheme: scheme, dynamicTypeSize: setting.size
            ))
            #expect(image.width == Int(setting.width), "one pixel a point")
            let marked = VStack(spacing: 0) {
                Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                sheet
            }
            let stops = marked.frame(width: setting.width)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElements(SnapshotAppearance(scheme, setting.size))
            let top = try #require(stops.first { $0.label == "Top" }).frame
            let save = try #require(stops.first { $0.label == "Save workout" }).frame
                .offsetBy(dx: -top.minX, dy: -top.maxY)
            let found = WorkoutRestPanelAdversarialTests.orange(in: image)
            // The button's fill is drawn up to 1.5 pt under its tappable frame at the largest size (one row of
            // pixels, measured): that is the fill, not another orange thing.
            let strays = found.filter { !save.insetBy(dx: -1, dy: -2).contains($0) }
            let box = strays.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1))) }
            return Orange(
                found: found.count,
                stray: strays.count,
                where: "strays in \(box), Save workout at \(save), image \(image.width)x\(image.height)"
            )
        }

        @Test(
            "Orange is Save workout's fill alone, at four sizes, both widths, bold, mirrored, both themes",
            arguments: [DynamicTypeSize.xSmall, .large, .accessibility2, .accessibility5],
            [ColorScheme.light, .dark]
        )
        func orange_isSaveWorkoutAlone(_ size: DynamicTypeSize, scheme: ColorScheme) throws {
            let words = WorkoutFinishWordsAdversarialTests.self
            let state = try words.workout(sets: 25, done: 23)
            let none = try words.workout(sets: 25, done: 0)
            for setting in LayoutSetting.sweep(size) {
                let name = "\(setting.testDescription) \(scheme)"
                let ready = WorkoutPresentation.finishSheet(state, isSaving: false, locale: Fixtures.locale)
                let withSets = try Self.orange(ready, setting, scheme)
                #expect(withSets.found > 500, "\(name): Save workout is orange")
                #expect(withSets.stray == 0, "\(name): \(withSets.stray) orange pixels outside: \(withSets.where)")
                let saving = WorkoutPresentation.finishSheet(state, isSaving: true, locale: Fixtures.locale)
                #expect(try Self.orange(saving, setting, scheme).found == 0, "\(name): orange while it saves")
                let empty = WorkoutPresentation.finishSheet(none, isSaving: false, locale: Fixtures.locale)
                #expect(try Self.orange(empty, setting, scheme).found == 0, "\(name): orange with nothing logged")
            }
        }
    }
#endif
