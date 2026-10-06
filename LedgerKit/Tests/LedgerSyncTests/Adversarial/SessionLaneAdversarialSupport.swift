import Foundation

/// F10 S3 criterion 9: how much of a seeded matrix of the adversarial session suites a lane runs. The nightly
/// plans run each matrix whole, as S1 and S2 wrote it; the PR plans and `swift test` run its first seeds or
/// set-ups, enough for every test, every kind of store and every fault to run at least once. No assertion
/// depends on the lane.
enum SessionLane {
    /// `full` in the nightly lane, its first `count` elsewhere.
    static func cut<Element>(_ full: some Collection<Element>, to count: Int) -> [Element] {
        TestLane.isNightly ? Array(full) : Array(full.prefix(count))
    }
}
