import Testing

/// The parent of every LedgerDesignTests suite that needs the main actor: the ones that render
/// with `ImageRenderer`, use the main-actor pixel helpers in `LedgerSnapshotTesting`, or build
/// UIKit trait collections.
///
/// Swift Testing starts every test case at once and starts each case's time allowance with it, so
/// a main-actor test that waits behind a minute of other rendering fails the plan's 60 s allowance
/// after doing a millisecond of work (F06 test findings, finding 19). The target's main actor runs
/// one job at a time anyway; serialising these suites costs no parallelism, and each test's clock
/// then starts when it actually runs. Suites that only compare values are `nonisolated` and stay
/// outside, running in parallel.
@Suite("Rendering (serialized)", .serialized)
enum RenderingSuites {}
