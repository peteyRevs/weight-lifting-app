@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criterion 9: the wording of onboarding's copy, the brief's "Copy (exact)" plus "Back". That it lives in
/// the catalog and in no other file is not this module's to test: `ModuleCopyTests` audits every module's sources
/// and asks each built bundle for its catalog's keys, and the gate compares each catalog with the compiler's
/// keys. This suite reads each line through the copy file, as standards §7 asks of a counted string.
@Suite("OnboardingCopy", .tags(.feature))
nonisolated struct OnboardingCopyTests {
    @Test("Step 3's sentence counts its weeks: one week, several weeks")
    func programBody_countsItsWeeks() {
        let one = OnboardingCopy.programBody(name: "Upper / Lower", weeks: 1, unit: "pounds", locale: Fixtures.locale)
        #expect(one == "Upper / Lower, 1 week, pounds. Editable any time.")
        let eight = OnboardingCopy.programBody(name: "Full Body", weeks: 8, unit: "kilograms", locale: Fixtures.locale)
        #expect(eight == "Full Body, 8 weeks, kilograms. Editable any time.")
        let none = OnboardingCopy.programBody(name: "Full Body", weeks: 0, unit: "pounds", locale: Fixtures.locale)
        #expect(none == "Full Body, 0 weeks, pounds. Editable any time.")
    }

    /// F08 S2/S3 port, ruling R8: the count takes the plural form of the catalog's language (`forCountedText`),
    /// so a lifter in a locale whose language counts otherwise still reads English as English counts it.
    @Test("The sentence's count takes the catalog's plural rule, not the locale's language", arguments: [
        ("fr_FR", 0, "A, 0 weeks, kg. Editable any time."), ("fr_FR", 1, "A, 1 week, kg. Editable any time."),
        ("ja_JP", 1, "A, 1 week, kg. Editable any time."), ("ru_RU", 21, "A, 21 weeks, kg. Editable any time.")
    ])
    func programBody_takesTheCatalogsPluralRule(identifier: String, weeks: Int, expected: String) {
        let locale = Locale(identifier: identifier)
        let body = OnboardingCopy.programBody(name: "A", weeks: weeks, unit: "kg", locale: locale)
        #expect(body == expected)
    }

    @Test("The units are named in words")
    func unitName_isAWord() {
        #expect(OnboardingCopy.unitName(.lb) == "pounds")
        #expect(OnboardingCopy.unitName(.kg) == "kilograms")
    }

    @Test("VoiceOver's line for the bars names the step and the count")
    func step_namesTheStepAndTheCount() {
        #expect(OnboardingCopy.step(1, of: 3, locale: Fixtures.locale) == "Step 1 of 3")
        #expect(OnboardingCopy.step(3, of: 3, locale: Fixtures.locale) == "Step 3 of 3")
    }

    @Test("The buttons and the failure line are the brief's")
    func buttonsAndFailure_areTheBriefs() {
        #expect(OnboardingCopy.continueTitle == "Continue")
        #expect(OnboardingCopy.startTraining == "Start training")
        #expect(OnboardingCopy.skipSetup == "Skip setup")
        #expect(OnboardingCopy.back == "Back")
        #expect(OnboardingCopy.retry == "Retry")
        #expect(OnboardingCopy.saveFailed == "Couldn't save your program. Try again.")
    }
}
