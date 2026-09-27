import Testing

/// Deviation from testing-strategy §6 (see F02 implementation notes): the tags live in the test
/// target, not LedgerTestSupport, because feature targets link LedgerTestSupport and tags there
/// would pull swift-testing into shipping code (F00 implementation notes #6).
extension Tag {
    /// Every LedgerDomain suite (layer tag).
    @Tag static var domain: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
}
