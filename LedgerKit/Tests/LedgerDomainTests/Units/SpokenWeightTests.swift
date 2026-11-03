import Foundation
@testable import LedgerDomain
import Testing

/// F13 S1, A6: weights and volumes as VoiceOver reads them, the unit's word in the form its number takes, never
/// "1 pounds"; the number is the one the screen draws, in the caller's locale.
@Suite("SpokenWeight", .tags(.domain))
struct SpokenWeightTests {
    static let english = Locale(identifier: "en_US")

    @Test("One pound is singular; 1.5 pounds, 185 pounds and 2 kilograms are plural")
    func weight_takesThePluralItsNumberTakes() {
        #expect(Weight.pounds(1).spoken(in: .lb, locale: Self.english) == "1 pound")
        #expect(Weight.pounds(1.5).spoken(in: .lb, locale: Self.english) == "1.5 pounds")
        #expect(Weight.pounds(185).spoken(in: .lb, locale: Self.english) == "185 pounds")
        #expect(Weight.kilograms(2).spoken(in: .kg, locale: Self.english) == "2 kilograms")
        #expect(Weight.kilograms(1).spoken(in: .kg, locale: Self.english) == "1 kilogram")
    }

    @Test("The number is the drawn one: 46.25, and 185 lb read in kilograms as 83.9")
    func weight_speaksTheDrawnNumber() {
        #expect(Weight.kilograms(46.25).spoken(in: .kg, locale: Self.english) == "46.25 kilograms")
        #expect(Weight.pounds(185).formatted(in: .kg) == "83.9")
        #expect(Weight.pounds(185).spoken(in: .kg, locale: Self.english) == "83.9 kilograms")
    }

    @Test("The spoken number is the drawn one as a Decimal, never read back from the drawn text (review R1-5)")
    func shownValue_isTheDrawnNumber() {
        #expect(Weight.pounds(185).shownValue(in: .kg) == Decimal(string: "83.9"))
        #expect(Weight.kilograms(46.25).shownValue(in: .kg) == Decimal(string: "46.25"))
        #expect(Weight.pounds(1_234_567).spoken(in: .lb, locale: Self.english) == "1,234,567 pounds")
    }

    @Test("A volume reads its whole number with the locale's grouping: 24,180 pounds, 1 pound, 0 pounds")
    func volume_readsItsWholeNumber() {
        let volume = Volume(weight: .pounds(186), reps: Reps(clamping: 130))
        #expect(volume.spoken(in: .lb, locale: Self.english) == "24,180 pounds")
        #expect(Volume(weight: .pounds(1), reps: Reps(clamping: 1)).spoken(in: .lb, locale: Self.english) == "1 pound")
        #expect(Volume.zero.spoken(in: .lb, locale: Self.english) == "0 pounds")
        #expect(volume.formatted(in: .lb) == "24,180", "the number the screen draws")
    }

    @Test("Another locale writes its own digits: ar_EG")
    func weight_inArabic_usesArabicDigits() {
        let spoken = Weight.pounds(185).spoken(in: .lb, locale: Locale(identifier: "ar_EG"))
        let arabicDigits = "\u{661}\u{668}\u{665}"
        #expect(spoken.hasPrefix(arabicDigits))
        #expect(!spoken.contains("185"))
    }
}
