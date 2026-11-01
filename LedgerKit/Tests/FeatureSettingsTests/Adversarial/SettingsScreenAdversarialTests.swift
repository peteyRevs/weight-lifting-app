#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S1b, G2: the page attacked with other languages and read as VoiceOver reads it.
    /// - German, Finnish and Tamil words, and Arabic right to left, at every size: one stop per row, nothing outside
    ///   the page, nothing over anything else.
    /// - A Persian week's Saturday as the menu's value.
    /// - The units' group named "Units", as VoiceOver would speak it.
    @MainActor
    @Suite("Settings screen, adversarial", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct SettingsScreenAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .xSmall, .large, .xxxLarge, .accessibility3, .accessibility5
        ]

        @Test(
            "N10. German, Finnish and Tamil words at every size: nothing outside the page, empty or overlapping",
            arguments: ["de", "fi", "ta"], sizes
        )
        func longWords_layOutSanely(_ language: String, _ size: DynamicTypeSize) {
            let words = ["de": SettingsWords.german, "fi": SettingsWords.finnish, "ta": SettingsWords.tamil][
                language
            ] ??
                SettingsWords.german
            let stops = SettingsWords.page(words).placedStops(SnapshotAppearance(.dark, size))
            #expect(stops.count == 14, "\(language) at \(size): \(stops.count) stops")
            let faults = SettingsLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(language) at \(size): \(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "Arabic, right to left, at every size: the same stops in the same order, laid out sanely, LB on the right",
            arguments: sizes
        )
        func arabic_rightToLeft(_ size: DynamicTypeSize) throws {
            let view = SettingsWords.page(SettingsWords.arabic).environment(\.layoutDirection, .rightToLeft)
            let stops = view.placedStops(SnapshotAppearance(.light, size))
            let labels = stops.map(\.stop.label)
            let expected = [SettingsWords.arabic.title, SettingsWords.arabic.problem, SettingsWords.arabic.training] +
                SettingsWords.arabic.spoken
                + [SettingsWords.arabic.rest, SettingsWords.arabic.week] + SettingsWords.arabic.switches.map(\.0)
                + [
                    SettingsWords.arabic.data,
                    "\(SettingsWords.arabic.health), \(SettingsWords.arabic.notConnected)",
                    SettingsWords.arabic.diagnostics
                ]
                + [SettingsWords.arabic.about]
            let inOrder = labels == expected
            #expect(inOrder, "\(size): \(labels)")
            let faults = SettingsLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(size): \(faults.prefix(4).joined(separator: "\n"))")
            let pounds = try #require(stops.first { $0.stop.label == SettingsWords.arabic.spoken[0] }).frame
            let kilograms = try #require(stops.first { $0.stop.label == SettingsWords.arabic.spoken[1] }).frame
            #expect(pounds.minX > kilograms.minX, "the first option leads, on the right")
            let week = try #require(stops.first { $0.stop.label == SettingsWords.arabic.week }).stop
            #expect(week.value == SettingsWords.arabic.weekValue)
        }

        @Test("N4. A Persian lifter's Saturday is the menu's value; the menu lists the week from Saturday")
        func persianWeek_menuValue() throws {
            var calendar = Calendar(identifier: .persian)
            calendar.locale = Locale(identifier: "fa_IR")
            var settings = Fixtures.settingsLb
            settings.weekStart = .saturday
            let model = SettingsPresentation.make(SettingsInput(
                settings: settings, about: SettingsFixtures.about, locale: Locale(identifier: "fa_IR"),
                calendar: calendar
            ))
            let stops = SettingsPage(model: model, send: { _ in }).environment(\.layoutDirection, .rightToLeft)
                .stops()
            let week = try #require(stops.first { $0.label == model.weekStart.title })
            #expect(week.value == "شنبه")
            #expect(model.weekStart.days.first?.title == "شنبه")
            #expect(model.weekStart.days.map(\.id) == [6, 7, 1, 2, 3, 4, 5])
        }

        // MARK: The units' group

        /// What holds `object`, as UIKit's accessibility tree says: an element's container, else a view's superview.
        static func parent(of object: NSObject) -> NSObject? {
            if let element = object as? UIAccessibilityElement {
                return element.accessibilityContainer as? NSObject
            }
            if let view = object as? UIView {
                return view.superview
            }
            let selector = NSSelectorFromString("accessibilityContainer")
            guard object.responds(to: selector) else {
                return nil
            }
            return object.perform(selector)?.takeUnretainedValue() as? NSObject
        }

        /// N5 and the component's doc: VoiceOver reads the two options as the group "Units". The row's own title is
        /// hidden from VoiceOver (`SettingsRowLabel`), so the group's name is the only place the word "Units" is heard,
        /// and VoiceOver speaks a container's label only for a semantic group. `SegmentedChoiceTests` leaves this to
        /// the DoD's manual check; here it is read from UIKit's tree, walking up from the option.
        @Test("N5. The units' options sit in a semantic group named \"Units\", which VoiceOver speaks")
        func unitsOptions_sitInAGroupNamedUnits() throws {
            let chain: [String] = SettingsParts(preview: .pounds).withAccessibilityElements { elements in
                guard let pounds = elements.first(where: { $0.accessibilityLabel == "pounds" }) else {
                    return []
                }
                var found: [String] = []
                var node = Self.parent(of: pounds)
                while let current = node, found.count < 12 {
                    let type = current.accessibilityContainerType
                    found.append("\(current.accessibilityLabel ?? "-")|\(type.rawValue)")
                    node = Self.parent(of: current)
                }
                return found
            }
            try #require(!chain.isEmpty, "the option was read, with what holds it")
            let named = chain.contains { $0.hasPrefix("Units|") }
            let semantic = "Units|\(UIAccessibilityContainerType.semanticGroup.rawValue)"
            let spoken = chain.contains(semantic)
            #expect(named, "a container is named Units: \(chain)")
            #expect(spoken, "the Units container is a semantic group: \(chain)")
        }
    }
#endif
