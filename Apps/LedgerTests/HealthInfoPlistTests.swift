import Foundation
import Testing

/// F16 criterion 1 (R1 §3.3): without either usage string, asking for authorization crashes. Twin: LedgerWatchTests.
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

    @Test("HealthKit is not a required device capability, so the app installs where Health is missing")
    func requiredCapabilities_omitHealthKit() {
        let capabilities = Self.info["UIRequiredDeviceCapabilities"] as? [String] ?? []
        #expect(!capabilities.contains("healthkit"))
    }
}
