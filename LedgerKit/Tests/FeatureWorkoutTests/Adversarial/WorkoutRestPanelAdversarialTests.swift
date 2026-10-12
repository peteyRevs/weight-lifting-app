#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S6 criteria 1, 10, 12 and 13: the rest panel as it is drawn. Every text size there is, not
    /// five; the panel's share of two phones and what is left of the page beside it; orange, by pixel; the
    /// VoiceOver stops from the brief's words; and `WorkoutRoot` itself, hosted, running the store's tasks.
    @MainActor
    @Suite("Rest panel (adversarial)", .serialized, .tags(.feature), .timeLimit(.minutes(5)))
    struct WorkoutRestPanelAdversarialTests {
        nonisolated static let everySize = DynamicTypeSize.allCases

        /// The panel's models: resting, at "Rest over", the longest words, a drop set in kilograms with a
        /// fraction, and no next set at all.
        static func models() throws -> [(name: String, model: RestPanelModel)] {
            var drop = try WorkoutPreview.dropSet.workout()
            drop.rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(3599), total: .seconds(3600))
            let last = drop.exercises.count - 1
            let dropRow = try #require(drop.exercises[last].sets.firstIndex { $0.kind == .drop })
            drop.cursor = Cursor(exerciseIndex: last, setIndex: dropRow)
            var none = try Fixtures.seedSession()
            for index in none.exercises[0].sets.indices {
                none.exercises[0].sets[index].doneAt = Fixtures.now
            }
            none.rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(61), total: .seconds(90))
            func panel(_ state: WorkoutState, _ selection: WorkoutSelection?) throws -> RestPanelModel {
                try #require(WorkoutPresentation.rest(
                    state, at: Fixtures.now.addingTimeInterval(1), selection: selection, isBusy: false,
                    locale: Fixtures.locale
                ))
            }
            return try [
                ("resting", RestPanelTests.model(.resting)),
                ("rest over", RestPanelTests.model(.restOver)),
                ("long words", RestPanelTests.longWords()),
                ("drop set", panel(drop, nil)),
                ("no next set", panel(none, WorkoutSelection(exerciseIndex: 0, setID: nil)))
            ]
        }

        @Test("The models are the ones meant: a drop set in kilograms, and one with no next set")
        func models_areTheOnesMeant() throws {
            let models = try Self.models()
            #expect(models[3].model.next?.line.hasPrefix("Drop set · ") == true)
            #expect(models[3].model.next?.line.contains(" kg × ") == true)
            #expect(models[4].model.next == nil)
            #expect(models[2].model.clock == "58:59")
        }

        // MARK: Criterion 13, at every text size

        @Test(
            "At every text size: no word cut, nothing outside the phone or over another, both buttons 44 pt",
            arguments: everySize
        )
        func panel_everySize(_ size: DynamicTypeSize) throws {
            for (name, model) in try Self.models() {
                let panel = RestPanel(model: model) { _ in }
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(in: panel, parts: RestPanelTests.parts(of: model), setting)
                    #expect(
                        cut.isEmpty,
                        "\(name), \(setting.testDescription): \(cut.prefix(2).joined(separator: "; "))"
                    )
                    let misplaced = WorkoutLayoutProbe.misplaced(in: panel, setting)
                    #expect(
                        misplaced.isEmpty,
                        "\(name), \(setting.testDescription): \(misplaced.prefix(2).joined(separator: "; "))"
                    )
                    let buttons = setting.elements(of: panel).filter { $0.traits.contains(.button) }
                    #expect(
                        buttons.map(\.label) == ["Add 30 seconds", "Skip rest"],
                        "\(name), \(setting.testDescription)"
                    )
                    let small = buttons.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                    #expect(small.isEmpty, "\(name), \(setting.testDescription): \(small.map(\.label))")
                }
            }
        }

        // MARK: Criterion 10: orange

        /// The pixels of `image` that are of the accent, as S5's check tells them: saturated orange.
        static func orange(in image: CGImage) -> [CGPoint] {
            guard let buffer = PixelBuffer(image) else {
                return []
            }
            return buffer.pixels.indices.compactMap { index in
                let pixel = buffer.pixels[index]
                let (red, green, blue) = (Int(pixel.red), Int(pixel.green), Int(pixel.blue))
                guard red >= 150, green * 2 <= red, blue * 3 <= red else {
                    return nil
                }
                return CGPoint(x: index % buffer.width, y: index / buffer.width)
            }
        }

        @Test(
            "Orange on the panel is the fill of Skip rest and the ring's arc, and nothing else, in both themes",
            arguments: [WorkoutPreview.resting, .restOver],
            [ColorScheme.light, .dark]
        )
        func orange_isSkipRestAndTheArc(_ preview: WorkoutPreview, scheme: ColorScheme) throws {
            let panel = try RestPanelTests.panel(preview)
            let width = SnapshotConfig.phoneWidth
            let image = try #require(RenderedImage.render(
                panel,
                width: width,
                colorScheme: scheme,
                dynamicTypeSize: .large
            ))
            #expect(image.width == Int(width), "one pixel a point")
            let marked = VStack(spacing: 0) {
                Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                panel
            }
            let stops = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, .large))
            let top = try #require(stops.first { $0.label == "Top" }).frame
            func place(_ label: (String) -> Bool) throws -> CGRect {
                try #require(stops.first { label($0.label) }).frame.offsetBy(dx: -top.minX, dy: -top.maxY)
            }
            let skip = try place { $0 == "Skip rest" }
            let extend = try place { $0 == "Add 30 seconds" }
            let reading = try place { $0.hasPrefix("Resting") || $0.hasPrefix("Rest over") }
            // The ring is the design system's 64 pt, at the reading's leading edge.
            let ring = CGRect(x: reading.minX, y: reading.minY, width: 64, height: reading.height).insetBy(
                dx: -1,
                dy: -1
            )
            let found = Self.orange(in: image)
            let inSkip = found.count { skip.contains($0) }
            let inRing = found.count { ring.contains($0) }
            #expect(inSkip > 500, "Skip rest is the panel's orange button")
            #expect(found.count { extend.contains($0) } == 0, "+30s is not orange")
            #expect(found.count == inSkip + inRing, "\(found.count - inSkip - inRing) orange pixels are elsewhere")
            if preview == .resting {
                #expect(inRing > 50, "the arc of a running rest is orange")
            } else {
                #expect(inRing == 0, "at Rest over the ring is empty")
            }
        }

        // MARK: Criterion 12: VoiceOver, from the brief's words

        @Test("On the screen VoiceOver meets the panel after the header and the page: time left, +30s, Skip rest")
        func screen_panelComesLast() {
            let outside = WorkoutScreenTests.screen(.resting)
                .accessibilityElements(SnapshotAppearance(.light, .large), outsideScrollViews: true)
            let last = outside.suffix(3)
            #expect(last.map(\.label) == ["Resting, Set 3, 200 pounds, 5 reps", "Add 30 seconds", "Skip rest"])
            #expect(last.map(\.value) == ["1 minute, 15 seconds", "", ""])
            #expect(last.first?.traits.contains(.updatesFrequently) == true, "not spoken again at every second")
            #expect(last.dropFirst().allSatisfy { $0.traits.contains(.button) })
            #expect(outside.first?.label == "Minimize", "the header comes first")
            // Below everything else on the screen.
            let panelTop = last.map(\.frame.minY).min() ?? 0
            #expect(outside.dropLast(3).allSatisfy { $0.frame.maxY <= panelTop + 0.5 })
        }
    }
#endif
