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

    @Test(
        """
        F04 fix round 2: remaining and fraction never trap. A huge interval saturates at 2^63 s; a \
        non-finite endsAt or now means no rest left (zero)
        """
    )
    func remainingAndFraction_saturate() {
        let cap = Duration.seconds(Double(Int64.max))
        let far = RestTimer(endsAt: Date(timeIntervalSinceReferenceDate: 1e21), total: .seconds(120))
        #expect(far.remaining(at: Fixtures.now) == cap)
        #expect(far.fraction(at: Fixtures.now) == 1)
        #expect(timer.remaining(at: Date(timeIntervalSinceReferenceDate: -1e308)) == cap)
        #expect(timer.remaining(at: Date(timeIntervalSinceReferenceDate: 1e308)) == .zero)
        for bad in [Double.nan, .infinity, -.infinity] {
            let date = Date(timeIntervalSinceReferenceDate: bad)
            let broken = RestTimer(endsAt: date, total: .seconds(120))
            #expect(broken.remaining(at: Fixtures.now) == .zero)
            #expect(broken.fraction(at: Fixtures.now) == 0)
            #expect(timer.remaining(at: date) == .zero)
            #expect(timer.fraction(at: date) == 0)
        }
    }
}
