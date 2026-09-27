import Foundation
@testable import LedgerDomain
import Testing

@Suite("RestTimer", .tags(.domain))
struct RestTimerTests {
    private let timer = RestTimer(endsAt: Fixtures.now, total: .seconds(120))

    @Test("Remaining time counts down to zero and never goes negative (rule 23)")
    func remaining_clampsAtZero() {
        #expect(timer.remaining(at: Fixtures.now.addingTimeInterval(-90)) == .seconds(90))
        #expect(timer.remaining(at: Fixtures.now) == .zero)
        #expect(timer.remaining(at: Fixtures.now.addingTimeInterval(30)) == .zero)
    }

    @Test("The fraction is the share of rest still to go, clamped to 0…1")
    func fraction_isShareRemaining() {
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(-30)) == 0.25)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(-500)) == 1)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(10)) == 0)
        #expect(RestTimer(endsAt: Fixtures.now, total: .zero).fraction(at: Fixtures.now) == 0)
    }
}
