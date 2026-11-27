import Foundation
import LedgerDomain
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S4: what the set screen's components are handed (the heart-rate line, the dots' and the crown's spoken words,
/// the crown's binding), and what the crown weight does with a VoiceOver swipe and with its binding.
@Suite("Watch components", .tags(.watch))
struct WatchWorkoutComponentTests {
    static let locale = Locale(identifier: "en_US")

    static func dial(_ weight: Weight, step: Weight, units: Units, turnedTo value: Double? = nil) -> CrownDial? {
        var crown = CrownWeightModel()
        let target = CrownWeightModel.Target(exerciseIndex: 0, setID: SetID(Fixtures.uuid(1)))
        crown.follow(CrownWeightModel.Reading(target: target, weight: weight, step: step, units: units))
        value.map { crown.rotate(to: $0) }
        return WatchPresentation.crownDial(crown, locale: locale)
    }

    @Test("The heart-rate line: the number and BPM, spoken in beats per minute; a dash and no reading without one")
    func heartRateLine_readingAndNone() {
        let sample = HeartRateSample(bpm: 142, date: Fixtures.now)
        let line = WatchPresentation.heartRateLine(sample, .authorized, locale: Self.locale)
        #expect(line == WatchHeartRateModel(
            value: "142", unit: "BPM", label: "Heart rate", spokenValue: "142 beats per minute"
        ))
        let one = HeartRateSample(bpm: 1, date: Fixtures.now)
        let oneLine = WatchPresentation.heartRateLine(one, .authorized, locale: Self.locale)
        #expect(oneLine.spokenValue == "1 beat per minute")
        for none in [
            WatchPresentation.heartRateLine(nil, .authorized, locale: Self.locale),
            WatchPresentation.heartRateLine(sample, .denied, locale: Self.locale)
        ] {
            #expect(none.value == "—" && none.unit == "BPM" && none.spokenValue == "No reading")
        }
    }

    @Test("The dots are spoken as the sets of the exercise logged")
    func ready_dotsSummary() throws {
        let session = try WatchSample.session()
        let fresh = try #require(WatchPresentation.ready(session, at: Fixtures.now, WatchSample.live()))
        #expect(fresh.dotsSummary == "0 of 5 sets logged")
        let state = WatchSample.logging([(0, 0), (0, 1)], in: session)
        let two = try #require(WatchPresentation.ready(state, at: Fixtures.now, WatchSample.live()))
        #expect(two.dots == [true, true, false, false, false] && two.dotsSummary == "2 of 5 sets logged")
    }

    @Test("The crown's dial: the number, its unit and words, its step and top, in pounds and in kilograms")
    func crownDial_poundsAndKilograms() throws {
        let pounds = try #require(Self.dial(.pounds(185), step: .pounds(5), units: .lb))
        #expect(pounds == CrownDial(
            weight: "185", unit: "LB", label: "Weight", spokenWeight: "185 pounds",
            value: 185, step: 5, upperBound: 2000
        ))
        let kilograms = try #require(Self.dial(.kilograms(102.5), step: .kilograms(2.5), units: .kg))
        #expect(kilograms.weight == "102.5" && kilograms.unit == "KG" && kilograms.spokenWeight == "102.5 kilograms")
        #expect(kilograms.step == 2.5 && kilograms.upperBound == 1000)
        let turned = try #require(Self.dial(.pounds(185), step: .pounds(5), units: .lb, turnedTo: 1025))
        #expect(turned.weight == "1025" && turned.spokenWeight == "1,025 pounds" && turned.value == 1025)
        #expect(WatchPresentation.crownDial(CrownWeightModel(), locale: Self.locale) == nil, "no set, no dial")
    }

    @Test("A VoiceOver swipe takes one step and rests, inside 0 through the top; the binding writes through")
    func crownWeight_adjustAndBinding() throws {
        var rotations: [Double] = []
        var rests = 0
        let dial = try #require(Self.dial(.pounds(185), step: .pounds(5), units: .lb))
        let weight = CrownWeight(dial: dial, onRotate: { rotations.append($0) }, onRest: { rests += 1 })
        weight.adjust(.increment)
        weight.adjust(.decrement)
        #expect(rotations == [190, 180] && rests == 2)
        let low = try #require(Self.dial(.pounds(0), step: .pounds(5), units: .lb))
        CrownWeight(dial: low, onRotate: { rotations.append($0) }, onRest: {}).adjust(.decrement)
        let top = try #require(Self.dial(.pounds(2000), step: .pounds(5), units: .lb))
        CrownWeight(dial: top, onRotate: { rotations.append($0) }, onRest: {}).adjust(.increment)
        #expect(rotations.suffix(2) == [0, 2000], "the swipe stays inside the crown's range")
        #expect(weight.rotation.wrappedValue == 185)
        weight.rotation.wrappedValue = 195
        #expect(rotations.last == 195 && rests == 2, "the binding turns; only onIdle rests")
    }
}
