import Foundation
import Testing

/// F16 criterion 1 (R1 §3.1, §3.3, D6): the watch shows its own authorization sheet, so it needs both usage strings,
/// and a session that plays haptics needs the audio background mode. Twin: LedgerTests.
@Suite("Health Info.plist")
struct HealthInfoPlistTests {
    static var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    @Test("Both Health usage strings are present, written out, with the display name filled in")
    func infoPlist_usageStringsPresent() {
        for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
            let text = Self.info[key] as? String ?? ""
            #expect(!text.isEmpty, "\(key)")
            #expect(!text.contains("$("), "\(key) has an unexpanded build setting")
        }
    }

    @Test("The background modes hold workout processing and audio, and nothing else")
    func watchBackgroundModes_containWorkoutProcessingAndAudio() {
        let modes = Self.info["WKBackgroundModes"] as? [String] ?? []
        #expect(Set(modes) == ["workout-processing", "audio"])
    }
}
