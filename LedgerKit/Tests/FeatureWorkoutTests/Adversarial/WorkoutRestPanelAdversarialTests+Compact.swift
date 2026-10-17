#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S6 round 2, ruling 17: the compact panel of the accessibility sizes. No ring; the two
    /// buttons side by side exactly where their words fit whole; at the largest size the next set spoken and
    /// not drawn; orange on "Skip rest" alone; and the page's room with Bold Text and a longer next-set line.
    extension WorkoutRestPanelAdversarialTests {
        nonisolated static let compactSizes: [DynamicTypeSize] = [
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        /// `model` with another next set, or none.
        static func model(_ model: RestPanelModel, next: RestPanelModel.NextSet?) -> RestPanelModel {
            RestPanelModel(
                clock: model.clock, fraction: model.fraction, status: model.status, spokenTime: model.spokenTime,
                isOver: model.isOver, next: next, extend: model.extend, extendLabel: model.extendLabel,
                skip: model.skip, isEnabled: model.isEnabled
            )
        }

        /// The one stop's size when `view` is given all the width it wants.
        static func whole(_ view: some View, _ setting: LayoutSetting) throws -> CGSize {
            let alone = setting.elements(of: view.fixedSize(), fixedWidth: false)
            try #require(alone.count == 1, "\(alone.count) stops, not one")
            return alone[0].frame.size
        }

        // MARK: "+30s" is whole too

        @Test(
            "+30s is drawn whole at every text size, in both arrangements",
            arguments: TestSweep.sizes(everySize)
        )
        func extend_isNeverCut(_ size: DynamicTypeSize) throws {
            for (name, model) in try Self.models() {
                let panel = RestPanel(model: model) { _ in }
                let part = LayoutPart(model.extendLabel) {
                    PillButton(model.extend, fillsWidth: true) {}.accessibilityLabel(Text(verbatim: model.extendLabel))
                }
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(in: panel, parts: [part], setting)
                    #expect(cut.isEmpty, "\(name), \(setting.testDescription): \(cut.joined(separator: "; "))")
                }
            }
        }

        // MARK: The switch between the two arrangements

        /// The panel as the screen places it, 16 pt from the cover's sides: the width its buttons have.
        @Test(
            "The compact panel's buttons stand side by side exactly where both words fit on one line",
            arguments: compactSizes
        )
        func buttons_sideBySide_exactlyWhereTheWordsFit(_ size: DynamicTypeSize) throws {
            let model = try RestPanelTests.model(.resting)
            let panel = PlacedRestPanel(model: model) { _ in }
            for setting in LayoutSetting.sweep(size) {
                let buttons = setting.elements(of: panel).filter { $0.traits.contains(.button) }
                try #require(buttons.count == 2)
                let (extend, skip) = (buttons[0].frame, buttons[1].frame)
                let isSideBySide = extend.maxX <= skip.minX + 0.5 || skip.maxX <= extend.minX + 0.5
                let extendWhole = try Self.whole(PillButton(model.extend, fillsWidth: true) {}, setting)
                let skipWhole = try Self.whole(PrimaryButton(model.skip) {}, setting)
                let inner = setting.width - 4 * LedgerSpacing.l
                let fits = extendWhole.width + LedgerSpacing.s + skipWhole.width <= inner + 0.5
                #expect(
                    isSideBySide == fits,
                    "\(setting.testDescription): \(extendWhole.width) + \(skipWhole.width) in \(inner)"
                )
                if isSideBySide {
                    #expect(
                        abs(skip.height - skipWhole.height) < 1,
                        "\(setting.testDescription): Skip rest is on one line"
                    )
                    #expect(skip.width >= skipWhole.width - 0.5, "\(setting.testDescription)")
                    #expect(extend.width >= extendWhole.width - 0.5, "\(setting.testDescription)")
                } else {
                    #expect(abs(extend.width - inner) < 1 && abs(skip.width - inner) < 1, "\(setting.testDescription)")
                    #expect(skip.minY >= extend.maxY, "\(setting.testDescription): +30s over Skip rest")
                }
            }
        }

        // MARK: The largest size: spoken, not drawn

        @Test(
            "At the largest size the next set is in what VoiceOver reads and takes no room; a size below, it is drawn"
        )
        func largest_nextSetIsSpokenNotDrawn() throws {
            let with = try RestPanelTests.model(.resting)
            let without = Self.model(with, next: nil)
            for setting in LayoutSetting.sweep(.accessibility5) + LayoutSetting.sweep(.accessibility4) {
                let drawn = setting.elements(of: RestPanel(model: with) { _ in })
                let bare = setting.elements(of: RestPanel(model: without) { _ in })
                #expect(drawn.map(\.label) == ["Resting, Set 3, 200 pounds, 5 reps", "Add 30 seconds", "Skip rest"])
                #expect(drawn.first?.value == "1 minute, 15 seconds")
                #expect(bare.first?.label == "Resting")
                let isSameSize = drawn.map(\.frame.size) == bare.map(\.frame.size)
                #expect(isSameSize == (setting.size == .accessibility5), "\(setting.testDescription)")
                let taps = drawn.filter { $0.traits.contains(.button) }
                #expect(taps.count == 2, "\(setting.testDescription): nothing else takes a tap")
            }
        }

        // MARK: Orange in the compact form

        @Test(
            "Orange on the compact panel is the fill of Skip rest and nothing else, in both themes",
            arguments: [WorkoutPreview.resting, .restOver],
            [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5]
        )
        func orange_compact_isSkipRestAlone(_ preview: WorkoutPreview, size: DynamicTypeSize) throws {
            for scheme in [ColorScheme.light, .dark] {
                let panel = try RestPanelTests.panel(preview)
                let width = SnapshotConfig.phoneWidth
                let image = try #require(
                    RenderedImage.render(panel, width: width, colorScheme: scheme, dynamicTypeSize: size)
                )
                let marked = VStack(spacing: 0) {
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                    panel
                }
                let stops = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, size))
                let top = try #require(stops.first { $0.label == "Top" }).frame
                let skip = try #require(stops.first { $0.label == "Skip rest" }).frame
                    .offsetBy(dx: -top.minX, dy: -top.maxY)
                    // A frame ends between two pixels: the pixel it ends in is the button's too.
                    .insetBy(dx: -1, dy: -1)
                let found = Self.orange(in: image)
                let inSkip = found.count { skip.contains($0) }
                #expect(inSkip > 500, "\(scheme): Skip rest is the panel's orange button")
                #expect(found.count == inSkip, "\(scheme): \(found.count - inSkip) orange pixels are elsewhere")
            }
        }

        // MARK: The page's room, with Bold Text and longer words

        static func room(
            on phone: CGSize,
            _ setting: LayoutSetting,
            rest: RestPanelModel
        ) throws -> CGFloat {
            let preview = WorkoutPreview.resting
            let screen = WorkoutScreen(model: preview.model, rest: rest) { _ in }
                .environment(\.workoutTimeline, .fixed(at: preview.now))
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.dynamicTypeSize, setting.size)
            let host = UIHostingController(rootView: screen)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            let found = try #require(WorkoutPageViewsAdversarialTests.scrollView(in: host.view))
            return found.bounds.height - found.adjustedContentInset.bottom
        }

        @Test("With Bold Text and with the longest next-set line, at least 120 pt of the page still show (ruling 17)")
        func room_withBoldTextAndLongerWords() throws {
            let models = try Self.models()
            for (name, model) in [models[0], models[3], models[2]] {
                for phone in Self.phones {
                    for isBold in [false, true] {
                        let rooms = try Self.everySize.map { size in
                            try Self.room(on: phone.size, LayoutSetting(size: size, isBold: isBold), rest: model)
                        }
                        let least = rooms.min() ?? 0
                        #expect(
                            least >= 120,
                            "\(name), \(phone.name)\(isBold ? ", bold" : ""): \(rooms.map { Int($0) })"
                        )
                    }
                }
            }
        }
    }
#endif
