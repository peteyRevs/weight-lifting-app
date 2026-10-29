#if DEBUG
    @testable import FeatureSettings
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureSettings is a case of `SettingsPreview`, and every case renders (the convention F07's
    /// criterion 8 set for each module with previews).
    @Suite("Previews (FeatureSettings)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureSettings is a Settings preview case, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureSettings")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(SettingsPreview.allCases.map(\.rawValue)))
            #expect(PreviewScan.registeredModules.contains("FeatureSettings"))
        }

        @Test("Every preview renders", arguments: SettingsPreview.allCases)
        func preview_renders(_ preview: SettingsPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every preview shows the state it is named for")
        func previews_showTheirStates() {
            let pounds = SettingsPreview.pounds.model()
            #expect(pounds.units.options.map(\.isSelected) == [true, false])
            #expect(pounds.weekStart.value == "Sunday" && pounds.switches.allSatisfy(\.isOn))
            let kilograms = SettingsPreview.kilograms.model()
            #expect(kilograms.units.options.map(\.isSelected) == [false, true])
            #expect(kilograms.rest.value == "2:30" && kilograms.weekStart.value == "Monday")
            #expect(kilograms.switches.map(\.isOn) == [false, true, false])
            let failed = SettingsPreview.saveFailed.model()
            #expect(failed.problem == "Couldn't save that change." && failed.rest.decrement == nil)
        }
    }
#endif
