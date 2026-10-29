@testable import FeatureHistory
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// FeatureHistory's counted texts through its copy file, with one and with several (standards §7), and the lookups
/// the presentation tests do not reach.
@Suite("HistoryCopy", .tags(.feature))
struct HistoryCopyTests {
    @Test("The badge counts its records: 1 PR, 3 PRs, 1,204 PRs")
    func records_oneAndSeveral() {
        #expect(HistoryCopy.records(1, locale: Fixtures.locale) == "1 PR")
        #expect(HistoryCopy.records(3, locale: Fixtures.locale) == "3 PRs")
        #expect(HistoryCopy.records(1204, locale: Fixtures.locale) == "1,204 PRs")
    }

    @Test("A length is drawn short and spoken whole: 1 min and 1 minute, 58 min and 58 minutes")
    func minutes_drawnAndSpoken() {
        #expect(HistoryCopy.minutes(1, locale: Fixtures.locale) == "1 min")
        #expect(HistoryCopy.minutes(58, locale: Fixtures.locale) == "58 min")
        #expect(HistoryCopy.spokenMinutes(1, locale: Fixtures.locale) == "1 minute")
        #expect(HistoryCopy.spokenMinutes(58, locale: Fixtures.locale) == "58 minutes")
    }

    @Test("Under a minute is drawn and spoken without a zero (F13-S1-2)")
    func underAMinute_drawnAndSpoken() {
        #expect(HistoryCopy.underAMinute == "<1 min")
        #expect(HistoryCopy.spokenUnderAMinute == "under a minute")
    }

    @Test("A counted text takes the catalog's plural form, not the locale's language's")
    func countedText_takesTheCatalogsPluralForm() {
        #expect(HistoryCopy.spokenMinutes(0, locale: Locale(identifier: "fr_FR")) == "0 minutes")
        #expect(HistoryCopy.records(1, locale: Locale(identifier: "ja_JP")) == "1 PR")
    }

    @Test("A volume names its unit")
    func volume_namesItsUnit() {
        #expect(HistoryCopy.volume("24,180", units: .lb, locale: Fixtures.locale) == "24,180 lb")
        #expect(HistoryCopy.volume("10,968", units: .kg, locale: Fixtures.locale) == "10,968 kg")
    }

    @Test("The failed state's two lines")
    func failed_readsItsTwoLines() {
        #expect(HistoryCopy.failedTitle == "Can't show your history right now")
        #expect(HistoryCopy
            .failedBody == "Your workouts are still on this iPhone. Open the app again to try once more.")
    }

    @Test("S2. The receipt's counted texts, with one and with several, as F10's catalog has them")
    func receipt_countedTexts() {
        #expect(HistoryCopy.setsLogged(done: "1", of: 1, locale: Fixtures.locale) == "1 of 1 set logged")
        #expect(HistoryCopy.setsLogged(done: "23", of: 25, locale: Fixtures.locale) == "23 of 25 sets logged")
        #expect(HistoryCopy.newRecords(1, locale: Fixtures.locale) == "1 new PR this session")
        #expect(HistoryCopy.newRecords(3, locale: Fixtures.locale) == "3 new PRs this session")
        #expect(HistoryCopy.moved("10,968", units: .kg, locale: Fixtures.locale) == "10,968 kg moved")
        #expect(HistoryCopy.movedTile(units: .kg) == "KG MOVED")
    }

    @Test("S2. A failed delete's alert and the unreadable workout's line")
    func deleteFailed_andUnreadable_readTheirLines() {
        #expect(HistoryCopy.deleteFailedTitle == "Couldn't delete this workout")
        #expect(HistoryCopy.deleteFailedBody == "It's still in your history. Try again in a moment.")
        #expect(HistoryCopy.okay == "OK")
        #expect(HistoryCopy.unreadableBody == "It stays in your history. You can still delete it.")
    }
}
