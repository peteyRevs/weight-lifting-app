import Testing

/// The tags live in the test target, not LedgerTestSupport, as in `LedgerDomainTests` (F02 notes): tags there
/// would pull swift-testing into every target that links it.
extension Tag {
    /// Every LedgerSync suite (layer tag, testing-strategy §6).
    @Tag static var sync: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
    /// Timing tests against a budget of architecture §15; nightly lane only (testing-strategy §6).
    @Tag static var performance: Self
    /// Tests that take more than about two seconds; nightly lane only (testing-strategy §6).
    @Tag static var slow: Self
}
