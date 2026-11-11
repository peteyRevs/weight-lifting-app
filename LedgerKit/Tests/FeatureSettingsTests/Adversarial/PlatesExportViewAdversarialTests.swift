#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F14 S2, G2 round 1, hosted: what VoiceOver hears of the export row (a share link read as one button, "Export
    /// data, CSV", with its line as the hint), of "Bar and plates" while Plate math is off (dimmed), and of the sheet
    /// (the bar adjustable, each plate one stop, an off-list size among them).
    @MainActor
    @Suite("Adversarial F14 S2 · plates and export, hosted", .tags(.feature), .timeLimit(.minutes(1)))
    struct PlatesExportViewAdversarialTests {
        static func page(_ settings: Settings) -> SettingsPage {
            SettingsPage(model: SettingsPresentation.make(SettingsInput(
                settings: settings,
                about: SettingsFixtures.about,
                export: WorkoutExport(fileName: "workouts-2026-09-16.csv", units: settings.units) {
                    throw CocoaError(.fileWriteUnknown)
                },
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )), send: { _ in })
        }

        @Test("The export row is one button, \"Export data, CSV\", with its line as the hint, enabled")
        func exportRow_isOneButton() throws {
            let stops = Self.page(Fixtures.settingsLb).stops()
            let export = stops.filter { $0.label.contains("Export") }
            try #require(export.count == 1, "\(export.count) stops name the export")
            #expect(export[0].kind == .button)
            #expect(export[0].label == "Export data, CSV")
            #expect(export[0].hint == "Every set you logged, in your current units")
            #expect(export[0].isEnabled)
            #expect(!stops.contains { $0.label.contains("Every set you logged") && $0.kind == .text })
        }

        @Test("With Plate math off, Bar and plates is one dimmed button that says why")
        func platesRow_dimmedWhileOff() throws {
            var settings = Fixtures.settingsLb
            settings.plateMathEnabled = false
            let rows = Self.page(settings).stops().filter { $0.label.contains("Bar and plates") }
            try #require(rows.count == 1, "\(rows.count) stops name the row")
            #expect(rows[0].kind == .button)
            #expect(!rows[0].isEnabled)
            let says = rows[0].label.contains("Turn on Plate math to edit") || rows[0].value
                .contains("Turn on Plate math")
            #expect(says, "\(rows[0])")
        }

        @Test("The sheet: the bar is adjustable with a spoken value, and every plate, off-list ones too, is one stop")
        func sheet_stops() {
            let draft = PlatesDraft(
                units: .lb,
                inventory: PlateInventory(bar: .pounds(45), plates: [45, 7.5].map(Weight.pounds))
            )
            let model = PlatesPresentation.sheet(draft, locale: Fixtures.locale)
            let stops = PlatesPage(model: model, send: { _ in }).stops()
            let bar = stops.filter { $0.kind == .adjustable }
            #expect(bar.map(\.label) == ["Bar"])
            #expect(bar.first?.value == "45 pounds")
            let plates = stops.filter { $0.label.hasSuffix("pounds") && $0.kind != .adjustable }
            #expect(plates.count == 10, "\(plates.count) plate stops")
            #expect(plates.contains { $0.label == "7.5 pounds" }, "the off-list size is a stop")
        }

        @Test("Each plate switch tells VoiceOver whether it is on: 45 and 7.5 on, 55 off")
        func sheet_platesSayOnOrOff() {
            let draft = PlatesDraft(
                units: .lb,
                inventory: PlateInventory(bar: .pounds(45), plates: [45, 7.5].map(Weight.pounds))
            )
            let model = PlatesPresentation.sheet(draft, locale: Fixtures.locale)
            let stops = PlatesPage(model: model, send: { _ in }).stops()
            func state(_ label: String) -> String {
                guard let stop = stops.first(where: { $0.label == label }) else {
                    return "missing"
                }
                if stop.isSelected || stop.value == "1" {
                    return "on"
                }
                return stop.value == "0" ? "off" : "no state"
            }
            let read = ["45 pounds", "7.5 pounds", "55 pounds"].map { "\($0): \(state($0))" }
            #expect(read == ["45 pounds: on", "7.5 pounds: on", "55 pounds: off"], "\(read)")
        }
    }
#endif
