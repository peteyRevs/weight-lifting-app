import Foundation
import LedgerDomain
import Testing

/// F19 S3b, Q12 (criterion 4): a device's "Last" line is the newer of its own history's and the phone's cached line.
@Suite("LastPerformance.newer", .tags(.domain))
struct LastPerformanceNewerTests {
    static let monday = Date(timeIntervalSinceReferenceDate: 811_228_800)

    static func line(_ seconds: TimeInterval, reps: Int) -> LastPerformance {
        LastPerformance(date: monday.addingTimeInterval(seconds), sets: 5, reps: reps, load: .pounds(185))
    }

    @Test("The newer date wins, whichever side holds it, by as little as a millisecond")
    func newerDateWins() {
        let older = Self.line(0, reps: 5)
        let newer = Self.line(0.001, reps: 3)
        #expect(LastPerformance.newer(own: newer, cached: older) == newer)
        #expect(LastPerformance.newer(own: older, cached: newer) == newer)
        let weekLater = Self.line(7 * 86400, reps: 8)
        #expect(LastPerformance.newer(own: older, cached: weekLater) == weekLater)
        #expect(LastPerformance.newer(own: weekLater, cached: older) == weekLater)
    }

    @Test("Of two lines with the same date, the cached one: the phone is the history authority (Q4)")
    func tieKeepsTheCachedLine() {
        let own = Self.line(0, reps: 5)
        let cached = Self.line(0, reps: 6)
        #expect(LastPerformance.newer(own: own, cached: cached) == cached)
        #expect(LastPerformance.newer(own: cached, cached: own) == own)
    }

    @Test("A missing side gives the other; both missing give none")
    func absentSides() {
        let line = Self.line(0, reps: 5)
        #expect(LastPerformance.newer(own: line, cached: nil) == line)
        #expect(LastPerformance.newer(own: nil, cached: line) == line)
        #expect(LastPerformance.newer(own: nil, cached: nil) == nil)
    }
}
