import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The crown's weight as a pure model (F18 criterion 4, the model half): the shown number while turning, one commit
/// on idle, the workout's number at rest, and what wins when the phone changes the set mid-turn.
@Suite("CrownWeightModel", .tags(.watch))
struct CrownWeightModelTests {
    static let target = CrownWeightModel.Target(exerciseIndex: 0, setID: SetID(Fixtures.uuid(1)))

    static func reading(_ weight: Weight, target: CrownWeightModel.Target = target) -> CrownWeightModel.Reading {
        CrownWeightModel.Reading(target: target, weight: weight, step: .pounds(5), units: .lb)
    }

    @Test("A turn shows at once, lands on the step, and commits once when the crown rests")
    func turn_commitsOnce() {
        var crown = CrownWeightModel()
        crown.rotate(to: 300)
        #expect(crown.weight == nil && !crown.isRotating, "no set, no turn")
        crown.follow(Self.reading(.pounds(185)))
        #expect(crown.value == 185)
        crown.rotate(to: 189.999_999)
        #expect(crown.isRotating && crown.weight == .pounds(190))
        #expect(crown.rotationEnded() == CrownWeightModel.Commit(target: Self.target, weight: .pounds(190)))
        #expect(crown.rotationEnded() == nil, "once")
        #expect(crown.value == 190 && crown.reading?.weight == .pounds(190), "the commit shows until the echo")
    }

    @Test("The phone's change mid-turn waits; the turn wins; a turn back gives way; a set logged meanwhile drops it")
    func remoteMidTurn() {
        var crown = CrownWeightModel()
        crown.follow(Self.reading(.pounds(185)))
        crown.rotate(to: 195)
        crown.follow(Self.reading(.pounds(225)))
        #expect(crown.value == 195)
        #expect(crown.rotationEnded()?.weight == .pounds(195))

        crown.follow(Self.reading(.pounds(195)))
        crown.rotate(to: 200)
        crown.follow(Self.reading(.pounds(135)))
        crown.rotate(to: 195)
        #expect(crown.rotationEnded() == nil && crown.value == 135)

        let next = CrownWeightModel.Target(exerciseIndex: 0, setID: SetID(Fixtures.uuid(2)))
        crown.rotate(to: 150)
        crown.follow(Self.reading(.pounds(140), target: next))
        #expect(crown.rotationEnded() == nil && crown.value == 140 && crown.reading?.target == next)
        crown.rotate(to: 145)
        crown.follow(nil)
        #expect(crown.rotationEnded() == nil && crown.weight == nil, "the workout ended mid-turn")
    }
}
