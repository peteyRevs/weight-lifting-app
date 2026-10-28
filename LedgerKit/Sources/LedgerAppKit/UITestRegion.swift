import Foundation
import LedgerDomain

/// The region a new install's settings start from (decision #15; F14 N3): the device's own, except under a UI test
/// (F14-S1-6), whose launch (`-LEDGER_UITEST`) always seeds the settings of a US iPhone, pounds and weeks from
/// Sunday, whatever region the simulator is set to. The onboarding tests' "…, pounds." and the nightly strip's first
/// day then read the same on every runner. The app's text is English alone (each catalog holds `en` only), so the
/// region is the one part of a UI test's launch that a runner could change.
nonisolated enum UITestRegion {
    /// A US iPhone's.
    static var settings: Settings {
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return .regional(locale: locale, calendar: calendar)
    }

    /// What the launch seeds a new install with: `settings` under a UI test, else the device's region.
    static func liveSettings(isUITest: Bool) -> Settings {
        isUITest ? settings : .regional(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent)
    }
}
